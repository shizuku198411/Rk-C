## Implements logical block device access on top of the active platform backend.
import ../../lib/types
import ../../platform/block_backend
import ../dev/console

const
  BlockSize* = U64(512)

var
  capacityBlocks: U64
  blockBaseOffset: U64
  initialized: bool


## Translates a logical block index into the active device LBA.
proc physicalBlockIndex(blockIndex: U64, outPhysical: var U64): bool =
  if blockIndex >= capacityBlocks:
    return false
  if blockBaseOffset + blockIndex < blockBaseOffset:
    return false

  let physical = blockBaseOffset + blockIndex
  if physical >= block_backend.physicalBlockCount():
    return false

  outPhysical = physical
  true


## Initializes the active platform block device backend.
proc blockdevInit*() =
  if block_backend.init(capacityBlocks) != 0:
    panic("block device init failed")

  blockBaseOffset = U64(0)
  initialized = true
  printBootMsg("  block device OK blocks = ")
  printUnsigned(capacityBlocks)
  putChar('\n')


## Restricts logical block operations to a partition or reserved range.
proc blockdevSetLogicalRange*(baseOffset, blockCount: U64): bool =
  if not initialized:
    return false
  if blockCount == U64(0):
    return false
  if baseOffset + blockCount < baseOffset:
    return false
  if baseOffset + blockCount > block_backend.physicalBlockCount():
    return false

  blockBaseOffset = baseOffset
  capacityBlocks = blockCount
  true


## Returns the current logical block base offset on the underlying device.
proc blockdevBaseOffset*(): U64 =
  blockBaseOffset


## Returns the current logical block capacity.
proc blockdevCapacityBlocks*(): U64 =
  capacityBlocks


## Reads one logical block.
proc blockRead*(blockIndex: U64, outBlock: pointer): int =
  if not initialized or outBlock == nil:
    return -1

  var physical = U64(0)
  if not physicalBlockIndex(blockIndex, physical):
    return -1

  block_backend.read(physical, outBlock)


## Writes one logical block.
proc blockWrite*(blockIndex: U64, inBlock: pointer): int =
  if not initialized or inBlock == nil:
    return -1

  var physical = U64(0)
  if not physicalBlockIndex(blockIndex, physical):
    return -1

  block_backend.write(physical, inBlock)
