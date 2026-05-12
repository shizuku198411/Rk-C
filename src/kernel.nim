import kernel/dev/console
import kernel/init/bootstrap
import kernel/task/process
import kernel/trap/trap
import kernel/trap/trap_types
import lib/string
import lib/types

discard sizeof(trap_types.TrapFrame)
discard cast[pointer](trap.trapHandler)
discard cast[pointer](string.strlen)


proc kernel_main*(hartid: U64, dtb: pointer) {.exportc, cdecl.} =
  kernelBootstrap(hartid, dtb)

  schedule()

  panic("scheduler returned to kernel_main")
