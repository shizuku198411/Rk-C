import kernel/dev/console
import kernel/dev/timer
import kernel/init/bootstrap
import kernel/task/exec
import kernel/task/process
import kernel/trap/trap
import kernel/trap/trap_types
import kernel/service/registry
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
  println("╚═══════════════════════════════════╝\n")


proc waitForRequiredServices() =
  while not requiredServicesReady():
    sleepCurrentUntilTick(timerTickCount + 1)


proc bootTask() {.cdecl.} =
  if createServiceManagerUserProcess() < 0:
    panic("failed to create service manager")

  waitForRequiredServices()

  if createShellUserProcess() < 0:
    panic("failed to create shell")

  if currentProc != nil:
    currentProc.detached = true

  kernelBanner()


proc kernel_main*(hartid: U64, dtb: pointer) {.exportc, cdecl.} =
  kernelBootstrap(hartid, dtb)

  if createKernelProcessNamed(bootTask, "boot_task") < 0:
    panic("failed to create boot task")

  schedule()

  panic("scheduler returned to kernel_main")
