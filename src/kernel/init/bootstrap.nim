## Boots the kernel, initializes subsystems, and starts initial user services.
import ../../arch/riscv64/arch
import ../../lib/calc
import ../../lib/mem
import ../../lib/types
import ../dev/console
import ../dev/timer
import ../fs/fs
import ../mm/memory
import ../mm/paging
import ../task/process
import ../task/exec
import ../service/registry

const
  ServiceWaitTimeoutTicks = U64(250)


var
  bssStartSym {.importc: "__bss_start".}: char
  bssEndSym {.importc: "__bss_end".}: char
  kernelBaseSym {.importc: "__kernel_base".}: char
  kernelEndSym {.importc: "__kernel_end".}: char
  stackBottomSym {.importc: "__stack_bottom".}: char
  stackTopSym {.importc: "__stack_top".}: char
  freeRamStartSym {.importc: "__free_ram_start".}: char
  freeRamEndSym {.importc: "__free_ram_end".}: char
  kernelRootPageTable: PageTable


## Clears bss.
proc clearBss() =
  let start = cast[U64](addr bssStartSym)
  let last = cast[U64](addr bssEndSym)
  let size = last - start
  zeroMem(cast[pointer](start), size)

  if not isZeroed(cast[pointer](start), size):
    panic("failed to bss zero clear")


## Sets trap vector.
proc setTrapVector() =
  arch.writeStvec(cast[U64](arch.trapEntry))


## Implements the enable timer interrupt kernel helper.
proc enableTimerInterrupt() =
  arch.writeSie(arch.readSie() or SieStie)
  arch.writeSstatus((arch.readSstatus() or SstatusSie) and not SstatusSum)


## Implements the enable sv39 kernel helper.
proc enableSv39(memInfo: MemoryInfo) =
  kernelRootPageTable = createKernelMappedPageTable()
  if kernelRootPageTable == nil:
    panic("failed to allocate kernel root page table")

  setKernelPageTable(kernelRootPageTable)
  let satp = makeSatp(cast[PAddr](kernelRootPageTable))
  paging.flushTlb()
  arch.writeSatp(satp)
  paging.flushTlb()

  discard memInfo


## Implements the kernel banner kernel helper.
proc kernelBanner() =
  putChar('\n')
  printlnConsoleOnly("╔════════════════════════════════════════╗")
  printlnConsoleOnly("║     ██████╗  ██╗  ██╗       ██████╗    ║")
  printlnConsoleOnly("║     ██╔══██╗ ██║ ██╔╝      ██╔════╝    ║")
  printlnConsoleOnly("║     ██████╔╝ █████╔╝ █████╗██║         ║")
  printlnConsoleOnly("║     ██╔══██╗ ██╔═██╗ ╚════╝██║         ║")
  printlnConsoleOnly("║     ██║  ██║ ██║  ██╗      ╚██████╗    ║")
  printlnConsoleOnly("║     ╚═╝  ╚═╝ ╚═╝  ╚═╝       ╚═════╝    ║")
  printlnConsoleOnly("╠════════════════════════════════════════╣")
  printlnConsoleOnly("║   microkernel-style system on RISC-V   ║")
  printlnConsoleOnly("║   version: 0.1.1                       ║")
  printlnConsoleOnly("╚════════════════════════════════════════╝\n")


## Waits for for initial services.
proc waitForInitialServices() =
  let deadline = saturatingAddU64(timerTickCount, ServiceWaitTimeoutTicks)

  while not allServicesReady():
    if timerTickCount >= deadline:
      if not requiredServicesReady():
        printBootMsg("  required service wait timeout\n")
        panic("required services did not become ready")

      printBootMsg("  optional service wait timeout; degraded boot\n")
      return

    sleepCurrentUntilTick(saturatingAddU64(timerTickCount, U64(1)))


## Implements the boot task kernel helper.
proc bootTask() {.cdecl.} =
  if createServiceManagerUserProcess() < 0:
    panic("failed to create service manager")

  waitForInitialServices()

  if createLoginUserProcess() < 0:
    panic("failed to create login")

  if currentProc != nil:
    currentProc.detached = true

  kernelBanner()



## Implements the address info kernel helper.
proc addressInfo(hartid: U64, dtb: pointer, memInfo: MemoryInfo) =
  let bssSize = cast[U64](addr bssEndSym) - cast[U64](addr bssStartSym)
  let freeRamSize = cast[U64](addr freeRamEndSym) - cast[U64](addr freeRamStartSym)

  printBootMsg("memory info:\n")
  printBootMsg("  hartid       = ")
  printUnsigned(hartid)
  putChar('\n')
  
  printBootMsg("  dtb          = ")
  printPtr(cast[U64](dtb))
  putChar('\n')

  printBootMsg("  bss start    = ")
  printPtr(cast[U64](addr bssStartSym))
  putChar('\n')
  printBootMsg("  bss end      = ")
  printPtr(cast[U64](addr bssEndSym))
  putChar('\n')
  printBootMsg("  bss size     = ")
  printUnsigned(bssSize)
  println(" bytes")

  printBootMsg("  kernel base  = ")
  printPtr(cast[U64](addr kernelBaseSym))
  putChar('\n')
  printBootMsg("  kernel end   = ")
  printPtr(cast[U64](addr kernelEndSym))
  putChar('\n')

  printBootMsg("  stack bottom = ")
  printPtr(cast[U64](addr stackBottomSym))
  putChar('\n')
  printBootMsg("  stack top    = ")
  printPtr(cast[U64](addr stackTopSym))
  putChar('\n')

  printBootMsg("  free ram             = ")
  printPtr(cast[U64](addr freeRamStartSym))
  print(" - ")
  printPtr(cast[U64](addr freeRamEndSym))
  putChar('\n')
  printBootMsg("  free ram size        = ")
  printUnsigned(freeRamSize)
  println(" bytes")
  printBootMsg("  managed region start = ")
  printPtr(memInfo.managedRegionStart)
  putChar('\n')
  printBootMsg("  total bitmap page    = ")
  printUnsigned(memInfo.bitmapPageCount)
  putChar('\n')
  printBootMsg("  total managed page   = ")
  printUnsigned(memInfo.managedPageCount)
  putChar('\n')
  printBootMsg("  kernel root pt       = ")
  printPtr(cast[U64](kernelRootPageTable))
  putChar('\n')


## Implements the kernel bootstrap kernel helper.
proc kernelBootstrap*(hartid: U64, dtb: pointer) =
  putChar('\n')

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

  printBootMsg("  enable timer interrupt ")
  setNextTimer()
  enableTimerInterrupt()
  println("OK")

  addressInfo(hartid, dtb, memInfo)
  print("\n")

  if createKernelProcessNamed(bootTask, "boot_task") < 0:
    panic("failed to create boot task")
