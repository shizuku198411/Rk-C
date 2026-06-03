## Dispatches optional toolchain installation policy to the active platform.
when defined(platformMilkVDuo256m):
  import ./milkv_duo256m/toolchain_policy as backend
else:
  import ./qemu_virt/toolchain_policy as backend


## Returns whether optional hosted toolchain libraries are installed at boot.
func installToolchainStdlibOnBoot*(): bool =
  backend.installToolchainStdlibOnBoot()
