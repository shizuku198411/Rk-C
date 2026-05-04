import kernel/dev/console
import kernel/init/bootstrap
import kernel/task/exec
import kernel/task/process
import kernel/trap/trap
import kernel/trap/trap_types
import lib/string
import lib/types

discard sizeof(trap_types.TrapFrame)
discard sizeof(CSize)
discard cast[pointer](trap.trapHandler)
discard cast[pointer](string.strlen)

proc kernel_main*(hartid: U64, dtb: pointer) {.exportc, cdecl.} =
  kernelBootstrap(hartid, dtb)

  if createShellUserProcess() < 0:
    panic("failed to create shell")

  schedule()

  panic("scheduler returned to kernel_main")
