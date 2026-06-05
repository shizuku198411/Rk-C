## Boots the kernel by coordinating runtime, filesystem, and userspace initialization.
import ../../lib/types
import ../dev/console
import ./runtime_setup

when defined(milkvBringup):
  import ./milkv_bringup
else:
  import ../dev/timer
  import ../fs/fs
  import ../mm/memory
  import ../task/process
  import ./userland_boot


## Initializes the selected kernel runtime and starts scheduling.
proc kernelBootstrap*(hartid: U64, dtb: pointer) =
  putChar('\n')

  when defined(milkvBringup):
    clearBss()
    milkvBringupBoot(hartid, dtb)
  else:
    printBootMsg("initial setup:\n")
    printBootMsg("  clear bss ")
    clearBss()
    println("OK")

    printBootMsg("  set trap vector ")
    setTrapVector()
    println("OK")

    printBootMsg("  initialize memory allocator ")
    let memInfo = memoryInit()
    println("OK")

    printBootMsg("  initialize process ")
    processInit()
    println("OK")

    printBootMsg("  enable Sv39 ")
    enableSv39(memInfo)
    println("OK")

    printBootMsg("initialize file system:\n")
    fsInit()

    printBootMsg("  enable external interrupt ")
    enableExternalInterrupts()
    println("OK")

    printBootMsg("  enable timer interrupt ")
    setNextTimer()
    enableTimerInterrupt()
    println("OK")

    addressInfo(hartid, dtb, memInfo)
    print("\n")

    if createKernelProcessNamed(bootTask, "boot_task") < 0:
      panic("failed to create boot task")
