## Provides a small read-only FDT scanner for platform bring-up diagnostics.
import ../../lib/fixed_string
import ../../lib/types

const
  FdtMagic = U32(0xd00dfeed)
  FdtBeginNode = U32(0x00000001)
  FdtEndNode = U32(0x00000002)
  FdtProp = U32(0x00000003)
  FdtNop = U32(0x00000004)
  FdtEnd = U32(0x00000009)
  MaxFdtSize = U64(2 * 1024 * 1024)
  MaxNodeDepth = 16
  MaxNodeNameLen = 64
  MaxTextLen* = 128
  MaxReservedRegions* = 8

type
  FdtHeaderInfo* = object
    valid*: bool
    magic*: U32
    totalSize*: U64
    offDtStruct*: U64
    offDtStrings*: U64
    offMemRsvmap*: U64
    version*: U32
    lastCompVersion*: U32
    sizeDtStrings*: U64
    sizeDtStruct*: U64

  FdtRegion* = object
    valid*: bool
    base*: U64
    size*: U64
    name*: array[MaxTextLen, char]

  FdtScanResult* = object
    header*: FdtHeaderInfo
    addressCells*: U32
    sizeCells*: U32
    stdoutPath*: array[MaxTextLen, char]
    memoryRegion*: FdtRegion
    reserveMapCount*: U64
    reserveMap*: array[MaxReservedRegions, FdtRegion]
    reservedMemoryCount*: U64
    reservedMemory*: array[MaxReservedRegions, FdtRegion]
    uart0Found*: bool
    plicFound*: bool
    clintFound*: bool
    sdFound*: bool
    ethernetFound*: bool
    scanOk*: bool

  FdtCpuInfo* = object
    valid*: bool
    hartCount*: U32
    firstHartId*: U64
    timebaseHz*: U64
    coreClockHz*: U64
    model*: array[MaxTextLen, char]
    compatible*: array[MaxTextLen, char]
    cpuCompatible*: array[MaxTextLen, char]
    isa*: array[MaxTextLen, char]
    mmuType*: array[MaxTextLen, char]


## Reads one byte from a raw pointer plus offset.
proc readU8(base: pointer, offset: U64): U8 =
  cast[ptr UncheckedArray[U8]](base)[offset]


## Reads one big-endian u32 from a raw pointer plus offset.
proc readBe32(base: pointer, offset: U64): U32 =
  (U32(readU8(base, offset)) shl 24) or
    (U32(readU8(base, offset + U64(1))) shl 16) or
    (U32(readU8(base, offset + U64(2))) shl 8) or
    U32(readU8(base, offset + U64(3)))


## Reads one big-endian u64 from a raw pointer plus offset.
proc readBe64(base: pointer, offset: U64): U64 =
  (U64(readBe32(base, offset)) shl 32) or U64(readBe32(base, offset + U64(4)))


## Rounds an FDT structure offset up to a 4-byte boundary.
proc alignFdt(value: U64): U64 =
  alignUp(value, U64(4))


## Returns whether an offset and length are inside the FDT blob.
proc rangeInside(totalSize, offset, length: U64): bool =
  if offset > totalSize:
    return false

  length <= totalSize - offset


## Copies an inline FDT C string into a fixed buffer.
proc copyInlineCString(blob: pointer, totalSize, offset: U64, dst: var openArray[char]): U64 =
  var i = U64(0)
  while i + U64(1) < U64(dst.len) and rangeInside(totalSize, offset + i, U64(1)):
    let ch = char(readU8(blob, offset + i))
    dst[i] = ch
    if ch == '\0':
      return i + U64(1)
    inc i

  if dst.len > 0:
    dst[dst.len - 1] = '\0'

  while rangeInside(totalSize, offset + i, U64(1)):
    if readU8(blob, offset + i) == U8(0):
      return i + U64(1)
    inc i

  U64(0)


## Returns whether a property name in the strings block matches the expected C string.
proc fdtStringEq(blob: pointer, header: FdtHeaderInfo, nameOff: U32, expected: cstring): bool =
  if expected == nil:
    return false

  let off = header.offDtStrings + U64(nameOff)
  if not rangeInside(header.totalSize, off, U64(1)):
    return false

  if U64(nameOff) >= header.sizeDtStrings:
    return false

  var i = U64(0)
  while U64(nameOff) + i < header.sizeDtStrings and rangeInside(header.totalSize, off + i, U64(1)):
    let ch = char(readU8(blob, off + i))
    if ch != expected[i]:
      return false

    if ch == '\0':
      return true

    inc i

  false


## Returns whether a fixed node name starts with a C string prefix.
proc fixedStartsWith(buf: openArray[char], prefix: cstring): bool =
  if prefix == nil:
    return false

  var i = 0
  while prefix[i] != '\0':
    if i >= buf.len or buf[i] != prefix[i]:
      return false
    inc i

  true


## Returns whether a fixed node name contains a C string needle.
proc fixedContains(buf: openArray[char], needle: cstring): bool =
  if needle == nil or needle[0] == '\0':
    return false

  var i = 0
  while i < buf.len and buf[i] != '\0':
    var j = 0
    while i + j < buf.len and buf[i + j] == needle[j]:
      inc j
      if needle[j] == '\0':
        return true
    inc i

  false


## Stores the first FDT string property value into a fixed buffer.
proc storeStringProperty(data: pointer, length: U64, dst: var openArray[char]) =
  if dst.len == 0:
    return

  let src = cast[ptr UncheckedArray[char]](data)
  var i = U64(0)
  while i + U64(1) < U64(dst.len) and i < length:
    dst[i] = src[i]
    if src[i] == '\0':
      return
    inc i

  dst[i] = '\0'


## Reads an address or size value from address/size cells.
proc readCellValue(data: pointer, length: U64, offset: var U64, cells: U32): U64 =
  if cells == U32(0) or cells > U32(2):
    return U64(0)

  if length < offset + U64(cells) * U64(4):
    return U64(0)

  var value = U64(0)
  var i = U32(0)
  while i < cells:
    value = (value shl 32) or U64(readBe32(data, offset))
    offset += U64(4)
    inc i

  value


## Stores a region in the next available result slot.
proc storeRegion(region: var FdtRegion, base, size: U64, name: openArray[char]) =
  region.valid = true
  region.base = base
  region.size = size
  copyChars(region.name, name)


## Reads a reg property as one base/size pair.
proc readRegRegion(data: pointer, length: U64, addressCells, sizeCells: U32, region: var FdtRegion, name: openArray[char]) =
  var offset = U64(0)
  let base = readCellValue(data, length, offset, addressCells)
  let size = readCellValue(data, length, offset, sizeCells)
  if size == U64(0):
    return

  storeRegion(region, base, size, name)


## Returns whether a fixed string buffer contains text.
proc fixedHasText(buf: openArray[char]): bool =
  buf.len > 0 and buf[0] != '\0'


## Reads and validates the FDT header.
proc fdtReadHeader*(blob: pointer): FdtHeaderInfo =
  if blob == nil:
    return FdtHeaderInfo(valid: false)

  result.magic = readBe32(blob, U64(0x00))
  result.totalSize = U64(readBe32(blob, U64(0x04)))
  result.offDtStruct = U64(readBe32(blob, U64(0x08)))
  result.offDtStrings = U64(readBe32(blob, U64(0x0c)))
  result.offMemRsvmap = U64(readBe32(blob, U64(0x10)))
  result.version = readBe32(blob, U64(0x14))
  result.lastCompVersion = readBe32(blob, U64(0x18))
  result.sizeDtStrings = U64(readBe32(blob, U64(0x20)))
  result.sizeDtStruct = U64(readBe32(blob, U64(0x24)))

  result.valid =
    result.magic == FdtMagic and
    result.totalSize >= U64(40) and
    result.totalSize <= MaxFdtSize and
    rangeInside(result.totalSize, result.offDtStruct, result.sizeDtStruct) and
    rangeInside(result.totalSize, result.offDtStrings, result.sizeDtStrings) and
    rangeInside(result.totalSize, result.offMemRsvmap, U64(16))


## Scans the FDT reservation map.
proc scanReserveMap(blob: pointer, result: var FdtScanResult) =
  var offset = result.header.offMemRsvmap
  while rangeInside(result.header.totalSize, offset, U64(16)):
    let base = readBe64(blob, offset)
    let size = readBe64(blob, offset + U64(8))
    offset += U64(16)

    if base == U64(0) and size == U64(0):
      return

    if result.reserveMapCount < MaxReservedRegions:
      let idx = result.reserveMapCount
      result.reserveMap[idx].valid = true
      result.reserveMap[idx].base = base
      result.reserveMap[idx].size = size
      discard copyCString(result.reserveMap[idx].name, cstring"memreserve")
      inc result.reserveMapCount


## Updates device candidate flags from one node name.
proc scanDeviceCandidate(nodeName: openArray[char], result: var FdtScanResult) =
  if fixedCStringEq(nodeName, cstring"serial@4140000") or fixedContains(nodeName, cstring"4140000"):
    result.uart0Found = true
  elif fixedCStringEq(nodeName, cstring"interrupt-controller@70000000") or fixedContains(nodeName, cstring"70000000"):
    result.plicFound = true
  elif fixedContains(nodeName, cstring"clint") or fixedContains(nodeName, cstring"74000000"):
    result.clintFound = true
  elif fixedContains(nodeName, cstring"cv-sd@4310000") or fixedContains(nodeName, cstring"4310000"):
    result.sdFound = true
  elif fixedContains(nodeName, cstring"ethernet@4070000") or fixedContains(nodeName, cstring"4070000"):
    result.ethernetFound = true


## Handles one property in the FDT structure block.
proc handleProperty(blob: pointer, result: var FdtScanResult, nodeNames: var array[MaxNodeDepth, array[MaxNodeNameLen, char]], depth: U64, nameOff: U32, data: pointer, length: U64) =
  if depth == U64(0):
    return

  let currentDepth = depth - U64(1)
  let current = nodeNames[currentDepth]
  var parent: array[MaxNodeNameLen, char]
  if currentDepth > U64(0):
    parent = nodeNames[currentDepth - U64(1)]

  if currentDepth == U64(0):
    if fdtStringEq(blob, result.header, nameOff, cstring"#address-cells") and length >= U64(4):
      result.addressCells = readBe32(data, U64(0))
    elif fdtStringEq(blob, result.header, nameOff, cstring"#size-cells") and length >= U64(4):
      result.sizeCells = readBe32(data, U64(0))
    return

  if fixedCStringEq(current, cstring"chosen"):
    if fdtStringEq(blob, result.header, nameOff, cstring"stdout-path") or
        fdtStringEq(blob, result.header, nameOff, cstring"linux,stdout-path"):
      storeStringProperty(data, length, result.stdoutPath)
  elif fixedStartsWith(current, cstring"memory") and
      fdtStringEq(blob, result.header, nameOff, cstring"reg"):
    readRegRegion(data, length, result.addressCells, result.sizeCells, result.memoryRegion, current)
  elif fixedCStringEq(parent, cstring"reserved-memory") and
      fdtStringEq(blob, result.header, nameOff, cstring"reg"):
    if result.reservedMemoryCount < MaxReservedRegions:
      let idx = result.reservedMemoryCount
      readRegRegion(data, length, result.addressCells, result.sizeCells, result.reservedMemory[idx], current)
      if result.reservedMemory[idx].valid:
        inc result.reservedMemoryCount


## Scans the FDT structure block for bring-up diagnostics.
proc scanStructBlock(blob: pointer, result: var FdtScanResult) =
  var nodeNames: array[MaxNodeDepth, array[MaxNodeNameLen, char]]
  var depth = U64(0)
  var offset = result.header.offDtStruct
  let endOffset = result.header.offDtStruct + result.header.sizeDtStruct

  result.addressCells = U32(2)
  result.sizeCells = U32(2)

  while offset < endOffset and rangeInside(result.header.totalSize, offset, U64(4)):
    let token = readBe32(blob, offset)
    offset += U64(4)

    case token
    of FdtBeginNode:
      if depth >= MaxNodeDepth:
        return

      let consumed = copyInlineCString(blob, result.header.totalSize, offset, nodeNames[depth])
      if consumed == U64(0):
        return

      scanDeviceCandidate(nodeNames[depth], result)
      offset = alignFdt(offset + consumed)
      inc depth

    of FdtEndNode:
      if depth == U64(0):
        return
      dec depth

    of FdtProp:
      if not rangeInside(result.header.totalSize, offset, U64(8)):
        return

      let length = U64(readBe32(blob, offset))
      let nameOff = readBe32(blob, offset + U64(4))
      offset += U64(8)

      if not rangeInside(result.header.totalSize, offset, length):
        return

      handleProperty(blob, result, nodeNames, depth, nameOff, cast[pointer](cast[U64](blob) + offset), length)
      offset = alignFdt(offset + length)

    of FdtNop:
      discard

    of FdtEnd:
      result.scanOk = true
      return

    else:
      return


## Scans basic FDT platform information.
proc fdtScanBasic*(blob: pointer): FdtScanResult =
  result.header = fdtReadHeader(blob)
  if not result.header.valid:
    return

  scanReserveMap(blob, result)
  scanStructBlock(blob, result)


## Handles one CPU-info property in the FDT structure block.
proc handleCpuProperty(blob: pointer, header: FdtHeaderInfo, result: var FdtCpuInfo, nodeNames: var array[MaxNodeDepth, array[MaxNodeNameLen, char]], depth: U64, nameOff: U32, data: pointer, length: U64, cpuAddressCells: var U32) =
  if depth == U64(0):
    return

  let currentDepth = depth - U64(1)
  let current = nodeNames[currentDepth]
  var parent: array[MaxNodeNameLen, char]
  if currentDepth > U64(0):
    parent = nodeNames[currentDepth - U64(1)]

  if currentDepth == U64(0):
    if fdtStringEq(blob, header, nameOff, cstring"model"):
      storeStringProperty(data, length, result.model)
    elif fdtStringEq(blob, header, nameOff, cstring"compatible"):
      storeStringProperty(data, length, result.compatible)
    return

  if fixedCStringEq(current, cstring"cpus"):
    if fdtStringEq(blob, header, nameOff, cstring"#address-cells") and length >= U64(4):
      cpuAddressCells = readBe32(data, U64(0))
    elif fdtStringEq(blob, header, nameOff, cstring"timebase-frequency") and length >= U64(4):
      result.timebaseHz = U64(readBe32(data, U64(0)))
    return

  if fixedCStringEq(parent, cstring"cpus") and fixedStartsWith(current, cstring"cpu@"):
    if fdtStringEq(blob, header, nameOff, cstring"reg") and length >= U64(4) and result.hartCount == U32(1):
      var offset = U64(0)
      result.firstHartId = readCellValue(data, length, offset, cpuAddressCells)
    elif fdtStringEq(blob, header, nameOff, cstring"compatible") and not fixedHasText(result.cpuCompatible):
      storeStringProperty(data, length, result.cpuCompatible)
    elif fdtStringEq(blob, header, nameOff, cstring"riscv,isa") and not fixedHasText(result.isa):
      storeStringProperty(data, length, result.isa)
    elif fdtStringEq(blob, header, nameOff, cstring"mmu-type") and not fixedHasText(result.mmuType):
      storeStringProperty(data, length, result.mmuType)
    elif fdtStringEq(blob, header, nameOff, cstring"clock-frequency") and length >= U64(4) and result.coreClockHz == U64(0):
      result.coreClockHz = U64(readBe32(data, U64(0)))


## Scans the FDT structure block for CPU description information.
proc scanCpuStructBlock(blob: pointer, header: FdtHeaderInfo, result: var FdtCpuInfo) =
  var nodeNames: array[MaxNodeDepth, array[MaxNodeNameLen, char]]
  var depth = U64(0)
  var offset = header.offDtStruct
  let endOffset = header.offDtStruct + header.sizeDtStruct
  var cpuAddressCells = U32(1)

  while offset < endOffset and rangeInside(header.totalSize, offset, U64(4)):
    let token = readBe32(blob, offset)
    offset += U64(4)

    case token
    of FdtBeginNode:
      if depth >= MaxNodeDepth:
        return

      let consumed = copyInlineCString(blob, header.totalSize, offset, nodeNames[depth])
      if consumed == U64(0):
        return

      if depth > U64(0) and fixedCStringEq(nodeNames[depth - U64(1)], cstring"cpus") and
          fixedStartsWith(nodeNames[depth], cstring"cpu@"):
        if result.hartCount == U32(0):
          result.firstHartId = U64(0)
        inc result.hartCount

      offset = alignFdt(offset + consumed)
      inc depth

    of FdtEndNode:
      if depth == U64(0):
        return
      dec depth

    of FdtProp:
      if not rangeInside(header.totalSize, offset, U64(8)):
        return

      let length = U64(readBe32(blob, offset))
      let nameOff = readBe32(blob, offset + U64(4))
      offset += U64(8)

      if not rangeInside(header.totalSize, offset, length):
        return

      handleCpuProperty(blob, header, result, nodeNames, depth, nameOff, cast[pointer](cast[U64](blob) + offset), length, cpuAddressCells)
      offset = alignFdt(offset + length)

    of FdtNop:
      discard

    of FdtEnd:
      result.valid = result.hartCount > U32(0)
      return

    else:
      return


## Scans CPU description information from an FDT blob.
proc fdtScanCpuInfo*(blob: pointer): FdtCpuInfo =
  let header = fdtReadHeader(blob)
  if not header.valid:
    return

  scanCpuStructBlock(blob, header, result)
