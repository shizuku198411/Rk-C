## Provides a no-op status LED backend for QEMU virt.


## Sets the platform status LED state.
proc setStatusLed*(on: bool): bool =
  discard on
  true
