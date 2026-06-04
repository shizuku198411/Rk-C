## Dispatches console I/O calls to the active platform backend.
import ../lib/types

when defined(platformMilkVDuo256m):
  import ./milkv_duo256m/console_backend as backend
else:
  import ./qemu_virt/console_backend as backend


## Reads the normalized status of the active platform console input.
proc inputStatus*(): U32 =
  backend.inputStatus()


## Reads one byte from the active platform console input.
proc readInput*(): int =
  backend.readInput()


## Writes one byte to the active platform console.
proc putChar*(ch: char) =
  backend.putChar(ch)


## Reads one byte from the active platform fallback console path.
proc tryGetFallback*(): int =
  backend.tryGetFallback()
