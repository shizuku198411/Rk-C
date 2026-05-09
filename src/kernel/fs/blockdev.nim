import ../../arch/riscv64/arch
import ../../lib/types
import ../dev/console
import ../mm/memory
import volatile

const
  BlockSize* = U64(512)
  BlockCount* = U64(32768)

  VirtioBlkIn = U32(0)
  VirtioBlkOut = U32(1)
  VqNum = U64(8)
  VqBytes = U64(8192)
  VqAlign = U64(4096)
  IoSpinLimit = U64(30000000)

  VirtioMmioBase = U64(0x10001000)
  VirtioMmioStride = U64(0x1000)
  VirtioMmioMaxDevs = U64(8)

  RegMagic = U64(0x000)
  RegVersion = U64(0x004)
  RegDeviceId = U64(0x008)
  RegVendorId = U64(0x00c)
  RegDeviceFeatures = U64(0x010)
  RegDeviceFeaturesSel = U64(0x014)
  RegDriverFeatures = U64(0x020)
  RegDriverFeaturesSel = U64(0x024)
  RegQueueSel = U64(0x030)
  RegQueueNumMax = U64(0x034)
  RegQueueNum = U64(0x038)
  RegQueueReady = U64(0x044)
  RegQueueNotify = U64(0x050)
  RegStatus = U64(0x070)
  RegQueueDescLow = U64(0x080)
  RegQueueDescHigh = U64(0x084)
  RegQueueAvailLow = U64(0x090)
  RegQueueAvailHigh = U64(0x094)
  RegQueueUsedLow = U64(0x0a0)
  RegQueueUsedHigh = U64(0x0a4)
  RegConfig = U64(0x100)

  VirtioMagic = U32(0x74726976)
  VirtioVendor = U32(0x554d4551)
  VirtioDevBlock = U32(2)

  StatusAcknowledge = U32(1)
  StatusDriver = U32(2)
  StatusDriverOk = U32(4)
  StatusFeaturesOk = U32(8)
  StatusFailed = U32(128)

  DescNext = U16(1)
  DescWrite = U16(2)
  FeatureVersion1 = U64(32)
  FeatureRingReset = U64(40)

type
  VirtqDesc {.packed.} = object
    paddr: U64
    len: U32
    flags: U16
    next: U16

  VirtqAvail {.packed.} = object
    flags: U16
    idx: U16
    ring: array[8, U16]
    usedEvent: U16

  VirtqUsedElem {.packed.} = object
    id: U32
    len: U32

  VirtqUsed {.packed.} = object
    flags: U16
    idx: U16
    ring: array[8, VirtqUsedElem]
    availEvent: U16

  VirtioBlkReqHdr {.packed.} = object
    typ: U32
    reserved: U32
    sector: U64

var
  mmioBase: U64
  capacityBlocks: U64
  vqMem: PAddr
  vqDesc: ptr UncheckedArray[VirtqDesc]
  vqAvail: ptr VirtqAvail
  vqUsed: ptr VirtqUsed
  vqLastUsedIdx: U16
  reqHdr: VirtioBlkReqHdr
  reqStatus: U8
  initialized: bool


proc mmioRead(off: U64): U32 =
  volatileLoad(cast[ptr U32](mmioBase + off))


proc mmioWrite(off: U64, val: U32) =
  volatileStore(cast[ptr U32](mmioBase + off), val)


proc findBlk(): bool =
  var i = U64(0)
  while i < VirtioMmioMaxDevs:
    let base = VirtioMmioBase + i * VirtioMmioStride
    if volatileLoad(cast[ptr U32](base + RegMagic)) == VirtioMagic and
        volatileLoad(cast[ptr U32](base + RegVersion)) >= 2 and
        volatileLoad(cast[ptr U32](base + RegDeviceId)) == VirtioDevBlock and
        volatileLoad(cast[ptr U32](base + RegVendorId)) == VirtioVendor:
      mmioBase = base
      return true
    inc i
  false


proc setupVqLayout() =
  if vqMem == NilPAddr:
    vqMem = palloc(VqBytes div PageSize)
    if vqMem == NilPAddr:
      panic("virtio vq alloc failed")

  let descBytes = U64(sizeof(VirtqDesc)) * VqNum
  vqDesc = cast[ptr UncheckedArray[VirtqDesc]](vqMem)
  vqAvail = cast[ptr VirtqAvail](vqMem + descBytes)
  vqUsed = cast[ptr VirtqUsed](vqMem + VqAlign)

  var p = cast[ptr UncheckedArray[U8]](vqMem)
  var i = U64(0)
  while i < VqBytes:
    p[i] = 0
    inc i
  vqLastUsedIdx = 0


proc setupQueue(): bool =
  mmioWrite(RegQueueSel, 0)
  let qmax = mmioRead(RegQueueNumMax)
  if qmax == 0 or qmax < U32(VqNum):
    return false

  mmioWrite(RegQueueNum, U32(VqNum))
  mmioWrite(RegQueueReady, 0)
  mmioWrite(RegQueueDescLow, U32(vqMem and 0xffffffff'u64))
  mmioWrite(RegQueueDescHigh, U32(vqMem shr 32))
  mmioWrite(RegQueueAvailLow, U32((cast[U64](vqAvail)) and 0xffffffff'u64))
  mmioWrite(RegQueueAvailHigh, U32(cast[U64](vqAvail) shr 32))
  mmioWrite(RegQueueUsedLow, U32((cast[U64](vqUsed)) and 0xffffffff'u64))
  mmioWrite(RegQueueUsedHigh, U32(cast[U64](vqUsed) shr 32))
  mmioWrite(RegQueueReady, 1)
  true


proc configureDevice(): bool =
  mmioWrite(RegStatus, 0)
  mmioWrite(RegStatus, StatusAcknowledge)
  mmioWrite(RegStatus, StatusAcknowledge or StatusDriver)

  mmioWrite(RegDeviceFeaturesSel, 0)
  discard mmioRead(RegDeviceFeatures)
  mmioWrite(RegDeviceFeaturesSel, 1)
  let features1 = mmioRead(RegDeviceFeatures)
  if (features1 and (U32(1) shl U32(FeatureVersion1 - 32))) == 0:
    println("[blk] missing VERSION_1")
    return false

  var accept1 = U32(1) shl U32(FeatureVersion1 - 32)
  let ringResetBit = U32(1) shl U32(FeatureRingReset - 32)
  if (features1 and ringResetBit) != 0:
    accept1 = accept1 or ringResetBit

  mmioWrite(RegDriverFeaturesSel, 0)
  mmioWrite(RegDriverFeatures, 0)
  mmioWrite(RegDriverFeaturesSel, 1)
  mmioWrite(RegDriverFeatures, accept1)

  var status = mmioRead(RegStatus) or StatusFeaturesOk
  mmioWrite(RegStatus, status)
  if (mmioRead(RegStatus) and StatusFeaturesOk) == 0:
    println("[blk] FEATURES_OK rejected")
    return false

  if not setupQueue():
    println("[blk] setup queue failed")
    return false

  status = mmioRead(RegStatus) or StatusDriverOk
  mmioWrite(RegStatus, status)
  true


proc readCapacity(): bool =
  let lo = U64(mmioRead(RegConfig + 0))
  let hi = U64(mmioRead(RegConfig + 4))
  capacityBlocks = (hi shl 32) or lo
  capacityBlocks != 0


proc doIo(typ: U32, blockIndex: U64, buf: pointer): int =
  reqHdr.typ = typ
  reqHdr.reserved = 0
  reqHdr.sector = blockIndex
  reqStatus = 0xff'u8

  vqDesc[0].paddr = cast[U64](addr reqHdr)
  vqDesc[0].len = U32(sizeof(reqHdr))
  vqDesc[0].flags = DescNext
  vqDesc[0].next = 1

  vqDesc[1].paddr = cast[U64](buf)
  vqDesc[1].len = U32(BlockSize)
  vqDesc[1].flags = DescNext
  if typ == VirtioBlkIn:
    vqDesc[1].flags = vqDesc[1].flags or DescWrite
  vqDesc[1].next = 2

  vqDesc[2].paddr = cast[U64](addr reqStatus)
  vqDesc[2].len = 1
  vqDesc[2].flags = DescWrite
  vqDesc[2].next = 0

  let availIdx = volatileLoad(addr vqAvail.idx)
  volatileStore(addr vqAvail.ring[availIdx mod U16(VqNum)], U16(0))
  arch.fenceRwRw()
  volatileStore(addr vqAvail.idx, availIdx + 1)
  arch.fenceRwRw()
  mmioWrite(RegQueueNotify, 0)

  var spin = U64(0)
  while volatileLoad(addr vqUsed.idx) == vqLastUsedIdx:
    inc spin
    if spin > IoSpinLimit:
      print("[blk] timeout type=")
      printUnsigned(U64(typ))
      print(" block=")
      printUnsigned(blockIndex)
      print(" status=")
      printHex(U64(volatileLoad(addr reqStatus)))
      print(" used=")
      printUnsigned(U64(volatileLoad(addr vqUsed.idx)))
      print(" last=")
      printUnsigned(U64(vqLastUsedIdx))
      putChar('\n')
      return -1

  vqLastUsedIdx = volatileLoad(addr vqUsed.idx)
  arch.fenceRwRw()

  if volatileLoad(addr reqStatus) != 0:
    print("[blk] io error type=")
    printUnsigned(U64(typ))
    print(" block=")
    printUnsigned(blockIndex)
    print(" status=")
    printHex(U64(volatileLoad(addr reqStatus)))
    putChar('\n')
    return -1
  0


proc blockdevInit*() =
  if not findBlk():
    panic("virtio-blk not found")

  setupVqLayout()
  if not configureDevice():
    mmioWrite(RegStatus, StatusFailed)
    panic("virtio-blk configure failed")
  if not readCapacity():
    mmioWrite(RegStatus, StatusFailed)
    panic("virtio-blk capacity failed")

  initialized = true
  printBootMsg("  virtio-blk OK blocks=")
  printUnsigned(capacityBlocks)
  putChar('\n')


proc blockRead*(blockIndex: U64, outBlock: pointer): int =
  if not initialized or outBlock == nil:
    return -1
  if blockIndex >= BlockCount or blockIndex >= capacityBlocks:
    return -1
  doIo(VirtioBlkIn, blockIndex, outBlock)


proc blockWrite*(blockIndex: U64, inBlock: pointer): int =
  if not initialized or inBlock == nil:
    return -1
  if blockIndex >= BlockCount or blockIndex >= capacityBlocks:
    return -1
  doIo(VirtioBlkOut, blockIndex, inBlock)
