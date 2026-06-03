## Dispatches console I/O calls to the active platform backend.
when defined(platformMilkVDuo256m):
  import ./milkv_duo256m/console_backend as backend
else:
  import ./qemu_virt/console_backend as backend


## Polls platform console input and pushes bytes into the caller-owned buffer.
proc pollInput*(push: proc(ch: char): bool): bool =
  backend.pollInput(push)


## Writes one byte to the active platform console.
proc putChar*(ch: char) =
  backend.putChar(ch)


## Reads one byte from the active platform fallback console path.
proc tryGetFallback*(): int =
  backend.tryGetFallback()
