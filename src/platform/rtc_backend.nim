## Dispatches wall-clock RTC reads to the active platform backend.
import ../lib/types

when defined(platformMilkVDuo256m):
  import ./milkv_duo256m/rtc_backend as backend
else:
  import ./qemu_virt/rtc_backend as backend


## Returns the active platform wall-clock time as Unix nanoseconds.
proc nowNanoseconds*(): U64 =
  backend.nowNanoseconds()
