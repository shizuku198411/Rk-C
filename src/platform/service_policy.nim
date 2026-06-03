## Dispatches service startup policy to the active platform.
when defined(platformMilkVDuo256m):
  import ./milkv_duo256m/service_policy as backend
else:
  import ./qemu_virt/service_policy as backend


## Returns the initial svcmgtd argument string.
func serviceManagerArgs*(): cstring =
  backend.serviceManagerArgs()
