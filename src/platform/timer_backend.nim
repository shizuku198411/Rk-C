## Dispatches timer programming to the active platform backend.
import ../lib/types

when defined(platformMilkVDuo256m):
  import ./milkv_duo256m/timer_backend as backend
else:
  import ./qemu_virt/timer_backend as backend


## Programs the next supervisor timer interrupt.
proc setNextTimer*(next: U64) =
  backend.setNextTimer(next)
