## Provides Milk-V Duo 256M filesystem boot layout policy.
import ../../kernel/dev/console
import ../../kernel/fs/blockdev
import ../../kernel/fs/partition
import ../../lib/types
import ./memory_layout


## Configures the Milk-V rootfs partition as the active logical block range.
proc configureBlockLayout*(): int =
  var part: BlockPartition
  if not readMbrPartition(MilkvAppfsPartitionIndex, part):
    return -1
  if not blockdevSetLogicalRange(part.startBlock, part.blockCount):
    return -1

  printBootMsg("  milkv rootfs base block = ")
  printUnsigned(blockdevBaseOffset())
  putChar('\n')
  printBootMsg("  milkv rootfs blocks = ")
  printUnsigned(blockdevCapacityBlocks())
  putChar('\n')
  printBootMsg("  milkv appfs local block = ")
  printUnsigned(MilkvAppfsLocalStartBlock)
  putChar('\n')
  0


## Returns whether appfs must use raw blockdev reads during service bootstrap.
func appfsUsesRawBlockDuringBootstrap*(): bool =
  true


## Returns the appfs start block relative to the logical rootfs partition.
func appfsBaseBlock*(): U64 =
  MilkvAppfsLocalStartBlock
