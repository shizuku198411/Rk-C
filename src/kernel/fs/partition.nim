## Parses simple MBR partition entries through the active block device.
import ../../lib/types
import ../dev/console
import ../fs/blockdev

const
  MbrSignatureOffset = U64(510)
  MbrPartitionTableOffset = U64(0x1be)
  MbrPartitionEntrySize = U64(16)
  MbrPartitionCount* = U64(4)
  MbrSignature = U16(0xaa55)
  MbrReadRetries = U64(4)

type
  BlockPartition* = object
    valid*: bool
    typ*: U8
    startBlock*: U64
    blockCount*: U64

var mbrBuf: array[512, U8]


## Prints a Milk-V MBR diagnostic line during early filesystem bootstrap.
proc printMbrDiag(label: cstring) =
  when defined(platformMilkVDuo256m):
    printBootMsg("  milkv mbr ")
    print(label)
    putChar('\n')


## Prints one Milk-V MBR diagnostic numeric value.
proc printMbrDiagValue(label: cstring, value: U64) =
  when defined(platformMilkVDuo256m):
    printBootMsg("  milkv mbr ")
    print(label)
    print(" = ")
    printUnsigned(value)
    putChar('\n')


## Prints one Milk-V MBR diagnostic hexadecimal value.
proc printMbrDiagHex(label: cstring, value: U64) =
  when defined(platformMilkVDuo256m):
    printBootMsg("  milkv mbr ")
    print(label)
    print(" = ")
    printHex(value)
    putChar('\n')


## Reads a little-endian U16 from the MBR buffer.
proc readLe16(buf: ptr UncheckedArray[U8], off: U64): U16 =
  U16(buf[off]) or (U16(buf[off + U64(1)]) shl 8)


## Reads a little-endian U32 from the MBR buffer.
proc readLe32(buf: ptr UncheckedArray[U8], off: U64): U32 =
  U32(buf[off]) or
    (U32(buf[off + U64(1)]) shl 8) or
    (U32(buf[off + U64(2)]) shl 16) or
    (U32(buf[off + U64(3)]) shl 24)


## Prints a compact snapshot of the last loaded MBR sector.
proc printMbrSectorSnapshot() =
  when defined(platformMilkVDuo256m):
    let buf = cast[ptr UncheckedArray[U8]](addr mbrBuf[0])
    printMbrDiagHex("word0", U64(readLe32(buf, U64(0))))
    printMbrDiagHex("word1", U64(readLe32(buf, U64(4))))
    printMbrDiagHex("word126", U64(readLe32(buf, U64(504))))
    printMbrDiagHex("word127", U64(readLe32(buf, U64(508))))


## Decodes one MBR partition entry from the last loaded sector.
proc decodeMbrPartition(index: U64, outPart: var BlockPartition): bool =
  let buf = cast[ptr UncheckedArray[U8]](addr mbrBuf[0])
  printMbrSectorSnapshot()
  let signature = readLe16(buf, MbrSignatureOffset)
  printMbrDiagHex("signature", U64(signature))
  if signature != MbrSignature:
    return false

  let off = MbrPartitionTableOffset + index * MbrPartitionEntrySize
  let typ = buf[off + U64(4)]
  let start = U64(readLe32(buf, off + U64(8)))
  let count = U64(readLe32(buf, off + U64(12)))
  printMbrDiagHex("partition type", U64(typ))
  printMbrDiagValue("partition start", start)
  printMbrDiagValue("partition blocks", count)
  if typ == U8(0) or start == U64(0) or count == U64(0):
    return false

  outPart.valid = true
  outPart.typ = typ
  outPart.startBlock = start
  outPart.blockCount = count
  true


## Reads one MBR partition entry from LBA 0.
proc readMbrPartition*(index: U64, outPart: var BlockPartition): bool =
  outPart = BlockPartition()
  if index >= MbrPartitionCount:
    printMbrDiag("index out of range")
    return false

  var attempt = U64(0)
  while attempt < MbrReadRetries:
    printMbrDiagValue("read attempt", attempt + U64(1))
    if blockRead(U64(0), addr mbrBuf[0]) != 0:
      printMbrDiag("block read failed")
      inc attempt
      continue

    if decodeMbrPartition(index, outPart):
      return true

    inc attempt

  false
