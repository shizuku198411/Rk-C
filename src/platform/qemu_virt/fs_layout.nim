## Provides QEMU virt filesystem boot layout policy.
import ../../lib/types


## Configures the QEMU filesystem block layout.
proc configureBlockLayout*(): int =
  0


## Returns whether appfs must use raw blockdev reads during service bootstrap.
func appfsUsesRawBlockDuringBootstrap*(): bool =
  false


## Returns the appfs start block relative to the logical rootfs partition.
func appfsBaseBlock*(): U64 =
  U64(0)
