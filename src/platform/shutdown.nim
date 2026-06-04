## Dispatches orderly shutdown to the active platform and provides a safe fallback.
import ../arch/riscv64/arch
import ../lib/types

when defined(platformMilkVDuo256m):
  import ./milkv_duo256m/shutdown as backend
else:
  import ./qemu_virt/shutdown as backend


proc sbiShutdown() {.importc: "sbi_shutdown", cdecl.}


## Stops supervisor interrupts and waits forever when poweroff is unsupported.
proc haltForever() {.noreturn.} =
  while true:
    arch.wfi()


## Attempts the platform-native poweroff path, then falls back to SBI shutdown.
proc powerOff*() {.noreturn.} =
  arch.writeSie(U64(0))
  arch.writeSstatus(arch.readSstatus() and not arch.SstatusSie)
  backend.tryPowerOff()
  sbiShutdown()
  haltForever()
