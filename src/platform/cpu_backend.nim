## Dispatches static CPU information to the active platform backend.
import ../lib/syscall_types

when defined(platformMilkVDuo256m):
  import ./milkv_duo256m/cpu_backend as backend
else:
  import ./qemu_virt/cpu_backend as backend


## Fills static CPU information for the active platform.
proc fillCpuStaticInfo*(info: var SysCpuStaticInfo) =
  backend.fillCpuStaticInfo(info)
