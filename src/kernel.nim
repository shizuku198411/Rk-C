import kernel/dev/console
import kernel/init/bootstrap
import kernel/task/exec
import kernel/task/process
import kernel/trap/trap
import kernel/trap/trap_types
import lib/string
import lib/types

discard sizeof(trap_types.TrapFrame)
discard cast[pointer](trap.trapHandler)
discard cast[pointer](string.strlen)


proc kernelBanner() =
  putChar('\n')
  println("╔═══════════════════════════════════╗")
  println("║  ██████╗  ██╗  ██╗       ██████╗  ║")
  println("║  ██╔══██╗ ██║ ██╔╝      ██╔════╝  ║")
  println("║  ██████╔╝ █████╔╝ █████╗██║       ║")
  println("║  ██╔══██╗ ██╔═██╗ ╚════╝██║       ║")
  println("║  ██║  ██║ ██║  ██╗      ╚██████╗  ║")
  println("║  ╚═╝  ╚═╝ ╚═╝  ╚═╝       ╚═════╝  ║")
  println("╠═══════════════════════════════════╣")
  println("║  version: 0.1.0                   ║")
  println("╚═══════════════════════════════════╝")


proc kernel_main*(hartid: U64, dtb: pointer) {.exportc, cdecl.} =
  kernelBootstrap(hartid, dtb)

  kernelBanner()

  if createShellUserProcess() < 0:
    panic("failed to create shell")

  schedule()

  panic("scheduler returned to kernel_main")
