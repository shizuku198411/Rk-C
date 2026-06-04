## Provides the QEMU shutdown backend before the common SBI fallback.


## Leaves QEMU poweroff to the common SBI shutdown fallback.
proc tryPowerOff*() =
  discard
