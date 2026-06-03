## Dispatches block device access to the active platform backend.
import ../lib/types

when defined(platformMilkVDuo256m):
  import ./milkv_duo256m/block_backend as backend
else:
  import ./qemu_virt/block_backend as backend


## Initializes the active platform block backend.
proc init*(outCapacityBlocks: var U64): int =
  backend.init(outCapacityBlocks)


## Returns the physical block capacity for bounds checking.
proc physicalBlockCount*(): U64 =
  backend.physicalBlockCount()


## Reads one physical block.
proc read*(blockIndex: U64, outBlock: pointer): int =
  backend.read(blockIndex, outBlock)


## Writes one physical block.
proc write*(blockIndex: U64, inBlock: pointer): int =
  backend.write(blockIndex, inBlock)
