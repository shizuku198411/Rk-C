## Dispatches kernel device MMIO mapping to the active platform.
import ../kernel/mm/paging

when defined(platformMilkVDuo256m):
  import ./milkv_duo256m/mmio_map as backend
else:
  import ./qemu_virt/mmio_map as backend


## Maps all kernel-visible platform device MMIO ranges.
proc mapPlatformDeviceRanges*(root: PageTable): int =
  backend.mapPlatformDeviceRanges(root)
