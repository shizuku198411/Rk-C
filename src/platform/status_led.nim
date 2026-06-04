## Dispatches status LED control to the active platform backend.
when defined(platformMilkVDuo256m):
  import ./milkv_duo256m/status_led as backend
else:
  import ./qemu_virt/status_led as backend


## Sets the active platform status LED state.
proc setStatusLed*(on: bool): bool =
  backend.setStatusLed(on)
