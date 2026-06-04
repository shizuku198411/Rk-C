## Provides Milk-V Duo 256M SD card block device access.
import ../../kernel/dev/console
import ../../kernel/dev/sd/sdhci
import ../../lib/types
import ./memory_layout

const
  MilkvSdBlockCount = U64(67_108_864)


## Initializes the Milk-V SD backend.
proc init*(outCapacityBlocks: var U64): int =
  outCapacityBlocks = MilkvSdBlockCount
  0


## Returns the physical block capacity for bounds checking.
proc physicalBlockCount*(): U64 =
  MilkvSdBlockCount


## Reads one physical SD block.
proc read*(blockIndex: U64, outBlock: pointer): int =
  let readResult = readBlock(MilkvSdBase, blockIndex, outBlock)
  if readResult.ok:
    return 0

  printBootMsg("  milkv sd read failed block = ")
  printUnsigned(blockIndex)
  print(" stage = ")
  printUnsigned(U64(ord(readResult.stage)))
  print(" int = ")
  printHex(U64(readResult.intStatus))
  print(" state = ")
  printHex(U64(readResult.presentState))
  putChar('\n')
  -1


## Writes one physical SD block.
proc write*(blockIndex: U64, inBlock: pointer): int =
  let writeResult = writeBlock(MilkvSdBase, blockIndex, inBlock)
  if writeResult.ok:
    return 0

  printBootMsg("  milkv sd write failed block = ")
  printUnsigned(blockIndex)
  print(" stage = ")
  printUnsigned(U64(ord(writeResult.stage)))
  print(" int = ")
  printHex(U64(writeResult.intStatus))
  print(" state = ")
  printHex(U64(writeResult.presentState))
  putChar('\n')
  -1


## Waits until the SD host reports no active command or data transfer.
proc sync*(): int =
  if syncSdhci(MilkvSdBase):
    return 0

  printBootMsg("  milkv sd sync failed\n")
  -1
