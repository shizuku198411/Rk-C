import kernel/bootstrap
import kernel/console
import kernel/exec
import kernel/process
import kernel/trap
import kernel/trap_types
import lib/string
import lib/types

discard sizeof(trap_types.TrapFrame)
discard sizeof(string.CSize)
discard cast[pointer](trap.trapHandler)

proc kernel_main*(hartid: U64, dtb: pointer) {.exportc, cdecl.} =
  kernelBootstrap(hartid, dtb)

  if createShellUserProcess() < 0:
    panic("failed to create shell")

  schedule()

  panic("scheduler returned to kernel_main")
