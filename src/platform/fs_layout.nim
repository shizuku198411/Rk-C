## Dispatches filesystem boot layout policy to the active platform.
import ../lib/types

when defined(platformMilkVDuo256m):
  import ./milkv_duo256m/fs_layout as backend
else:
  import ./qemu_virt/fs_layout as backend


## Configures the active platform filesystem block layout.
proc configureBlockLayout*(): int =
  backend.configureBlockLayout()


## Returns whether appfs must use raw blockdev reads during service bootstrap.
func appfsUsesRawBlockDuringBootstrap*(): bool =
  backend.appfsUsesRawBlockDuringBootstrap()


## Returns the platform appfs base block.
func appfsBaseBlock*(): U64 =
  backend.appfsBaseBlock()
