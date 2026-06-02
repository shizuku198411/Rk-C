## Boots the kernel, initializes subsystems, and starts initial user services.
import ../../arch/riscv64/arch
import ../../lib/calc
import ../../lib/mem
import ../../lib/types
import ../../lib/user_ids
import ../../generated/version
import ../dev/console
import ../dev/timer
import ../fs/fs
import ../mm/memory
import ../mm/paging
import ../task/process
import ../task/exec
import ../service/registry

when defined(platformMilkVDuo256m):
  import ../../platform/milkv_duo256m/memory_layout

const
  ServiceWaitTimeoutTicks = U64(250)
  ToolchainInstallerPath = "/bin/rkcstdlib"
  ToolchainStdioHeaderPath = "/usr/include/rkc_stdio.h"
  ToolchainStdlibHeaderPath = "/usr/include/rkc_stdlib.h"
  ToolchainStringHeaderPath = "/usr/include/rkc_string.h"
  ToolchainUnistdHeaderPath = "/usr/include/rkc_unistd.h"
  ToolchainStdioLibraryPath = "/usr/lib/rkc_stdio.rko"
  ToolchainStdlibLibraryPath = "/usr/lib/rkc_stdlib.rko"
  ToolchainStringLibraryPath = "/usr/lib/rkc_string.rko"
  ToolchainUnistdLibraryPath = "/usr/lib/rkc_unistd.rko"
  ToolchainInstallArgs = "--install"


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
proc printBannerVersionLine() =
  printConsoleOnly("║   version: ")
  printConsoleOnly(cstring(RkcVersion))

  var spaces = 40 - 12 - RkcVersion.len
  while spaces > 0:
    putChar(' ')
    dec spaces

  printlnConsoleOnly("║")


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
  printBannerVersionLine()
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


## Waits for one kernel-launched userspace setup process and reaps it.
proc waitForSetupProcess(pid: int32): U64 =
  var target = findProcessByPid(pid)
  while target != nil and target.state != procZombie:
    sleepCurrentForPid(pid)
    target = findProcessByPid(pid)

  if target == nil:
    return U64(-1'i64)

  let status = target.exitStatus
  discardProcess(target)
  status


## Tests whether every split optional toolchain library artifact is installed.
proc toolchainStdlibInstalled(): bool =
  fsFileSize(cstring(ToolchainStdioHeaderPath)) >= 0 and
    fsFileSize(cstring(ToolchainStdlibHeaderPath)) >= 0 and
    fsFileSize(cstring(ToolchainStringHeaderPath)) >= 0 and
    fsFileSize(cstring(ToolchainUnistdHeaderPath)) >= 0 and
    fsFileSize(cstring(ToolchainStdioLibraryPath)) >= 0 and
    fsFileSize(cstring(ToolchainStdlibLibraryPath)) >= 0 and
    fsFileSize(cstring(ToolchainStringLibraryPath)) >= 0 and
    fsFileSize(cstring(ToolchainUnistdLibraryPath)) >= 0


## Installs optional hosted toolchain library files before login when absent.
proc maybeInstallToolchainStdlib() =
  if fsFileSize(cstring(ToolchainInstallerPath)) < 0:
    return
  printBootMsg(" optional toolchain is installed.\n")
  if toolchainStdlibInstalled():
    printBootMsg(" standard library already installed.\n")
    return

  let pid = execUserAppAs(
    cstring(ToolchainInstallerPath),
    cstring(ToolchainInstallArgs),
    RootUid,
    RootGid,
  )
  if pid < 0 or waitForSetupProcess(pid) != U64(0):
    printBootMsg(" install optional toolchain standard library ... FAIL\n")
    return

  printBootMsg(" install optional toolchain standard library ... OK\n")


## Implements the boot task kernel helper.
proc bootTask() {.cdecl.} =
  if createServiceManagerUserProcess() < 0:
    panic("failed to create service manager")

  waitForInitialServices()

  maybeInstallToolchainStdlib()

  if createLoginUserProcess() < 0:
    panic("failed to create login")

  if currentProc != nil:
    currentProc.detached = true

  kernelBanner()


when defined(milkvBringup):
  const
    MilkvTimerDelta = U64(250000)


  proc sbiSetTimer(value: U64) {.importc: "sbi_set_timer", cdecl.}


  ## Prints one Milk-V bring-up log prefix.
  proc printMilkvPrefix() =
    printConsoleOnly("[milkv] ")


  ## Prints one Milk-V bring-up status line.
  proc printMilkvStatus(label: cstring, status: cstring) =
    printMilkvPrefix()
    printConsoleOnly(label)
    printConsoleOnly(" ... ")
    printlnConsoleOnly(status)


  ## Prints one address line for Milk-V Duo 256M bring-up mode.
  proc printBringupAddress(label: cstring, value: U64) =
    printConsoleOnly(label)
    printPtr(value)
    putChar('\n')


  ## Prints one Milk-V labeled hexadecimal value.
  proc printMilkvHex(label: cstring, value: U64) =
    printMilkvPrefix()
    printConsoleOnly(label)
    printConsoleOnly(" = ")
    printPtr(value)
    putChar('\n')


  ## Prints one Milk-V labeled decimal value.
  proc printMilkvUnsigned(label: cstring, value: U64) =
    printMilkvPrefix()
    printConsoleOnly(label)
    printConsoleOnly(" = ")
    printUnsigned(value)
    putChar('\n')


  ## Stops the kernel in a low-noise loop after bring-up logging.
  proc enterBringupLoop() =
    printlnConsoleOnly("[milkv] entering wfi loop")
    while true:
      arch.wfi()


  ## Logs the current S-mode CSR snapshot for Milk-V bring-up.
  proc printMilkvCsrSnapshot() =
    printMilkvPrefix()
    printlnConsoleOnly("csr snapshot:")
    printMilkvHex("  sstatus", arch.readSstatus())
    printMilkvHex("  sie    ", arch.readSie())
    printMilkvHex("  satp   ", arch.readSatp())
    printMilkvHex("  stvec  ", arch.readStvec())
    printMilkvHex("  sscratch", arch.readSscratch())
    printMilkvHex("  scounteren", arch.readScounteren())


  ## Sets and verifies the trap vector without enabling interrupts.
  proc checkMilkvTrapVector() =
    setTrapVector()
    printMilkvStatus("trap vector", "OK")
    printMilkvHex("  trap_entry", cast[U64](arch.trapEntry))
    printMilkvHex("  stvec     ", arch.readStvec())


  ## Performs a one-shot SBI timer call while interrupts remain disabled.
  proc checkMilkvTimerCall() =
    let now = arch.rdtime()
    let next = now + MilkvTimerDelta
    printMilkvHex("  time", now)
    sbiSetTimer(next)
    printMilkvHex("  next timer", next)
    printMilkvStatus("timer call", "OK")


  ## Checks whether an address is inside the early managed memory window.
  proc milkvAddressInManagedRange(value: U64): bool =
    value >= MilkvEarlyManagedStart and value < MilkvEarlyManagedEnd


  ## Checks whether one memory range intersects the early managed memory window.
  proc milkvRangeOverlapsManagedRange(start, last: U64): bool =
    start < MilkvEarlyManagedEnd and last > MilkvEarlyManagedStart


  ## Prints the early memory range candidate for the next bring-up phase.
  proc printMilkvMemoryCandidate(dtb: pointer) =
    printMilkvPrefix()
    printlnConsoleOnly("memory candidate:")
    printMilkvHex("  kernel end", cast[U64](addr kernelEndSym))
    printMilkvHex("  free start", MilkvEarlyManagedStart)
    printMilkvHex("  free end  ", MilkvEarlyManagedEnd)
    printMilkvHex("  fdt       ", cast[U64](dtb))

    let fdtAddr = cast[U64](dtb)
    if milkvAddressInManagedRange(fdtAddr):
      printMilkvStatus("fdt range", "WARN")
    else:
      printMilkvStatus("fdt range", "OK")


  ## Verifies that the early allocator window is safe for Phase 2 use.
  proc validateMilkvMemoryWindow(dtb: pointer): bool =
    let kernelBase = cast[U64](addr kernelBaseSym)
    let kernelEnd = cast[U64](addr kernelEndSym)
    let stackBottom = cast[U64](addr stackBottomSym)
    let stackTop = cast[U64](addr stackTopSym)
    let fdtAddr = cast[U64](dtb)

    printMilkvPrefix()
    printlnConsoleOnly("phase2 memory validation:")

    var ok = true

    if MilkvKernelLoadBase == kernelBase:
      printMilkvStatus("  kernel load base", "OK")
    else:
      printMilkvStatus("  kernel load base", "FAIL")
      ok = false

    if MilkvEarlyManagedStart < MilkvEarlyManagedEnd:
      printMilkvStatus("  managed range order", "OK")
    else:
      printMilkvStatus("  managed range order", "FAIL")
      ok = false

    if kernelEnd <= MilkvEarlyManagedStart:
      printMilkvStatus("  kernel outside managed", "OK")
    else:
      printMilkvStatus("  kernel outside managed", "FAIL")
      ok = false

    if not milkvRangeOverlapsManagedRange(stackBottom, stackTop):
      printMilkvStatus("  stack outside managed", "OK")
    else:
      printMilkvStatus("  stack outside managed", "FAIL")
      ok = false

    if not milkvAddressInManagedRange(fdtAddr):
      printMilkvStatus("  fdt outside managed", "OK")
    else:
      printMilkvStatus("  fdt outside managed", "FAIL")
      ok = false

    if MilkvEarlyManagedEnd <= MilkvReservedIonStart:
      printMilkvStatus("  reserved ion outside managed", "OK")
    else:
      printMilkvStatus("  reserved ion outside managed", "FAIL")
      ok = false

    if fdtAddr == MilkvKnownFdtAddr:
      printMilkvStatus("  known fdt address", "OK")
    else:
      printMilkvStatus("  known fdt address", "WARN")

    ok


  ## Initializes the physical allocator with the validated Milk-V early range.
  proc initMilkvPhase2Memory(): MemoryInfo =
    let memInfo = initMemoryAllocator(MilkvEarlyManagedStart, MilkvEarlyManagedEnd)
    printMilkvPrefix()
    printlnConsoleOnly("allocator:")
    printMilkvHex("  bitmap start", memInfo.freeRamStart)
    printMilkvUnsigned("  bitmap pages", memInfo.bitmapPageCount)
    printMilkvHex("  managed start", memInfo.managedRegionStart)
    printMilkvUnsigned("  managed pages", memInfo.managedPageCount)
    memInfo


  ## Exercises palloc/pfree once so real hardware can validate allocator basics.
  proc runMilkvAllocatorSmokeTest() =
    let before = bitmapInfo()
    printMilkvPrefix()
    printlnConsoleOnly("allocator smoke:")
    printMilkvUnsigned("  total pages before", before.total)
    printMilkvUnsigned("  used pages before ", before.used)
    printMilkvUnsigned("  free pages before ", before.free)

    let pageA = palloc(U64(1))
    let pageB = palloc(U64(1))
    printMilkvHex("  page A", pageA)
    printMilkvHex("  page B", pageB)

    if pageA == NilPAddr or pageB == NilPAddr or pageA == pageB:
      printMilkvStatus("  allocate pages", "FAIL")
      return

    cast[ptr U64](pageA)[] = U64(0x1122334455667788)
    cast[ptr U64](pageB)[] = U64(0x8877665544332211)

    let afterAlloc = bitmapInfo()
    if afterAlloc.used == before.used + U64(2):
      printMilkvStatus("  allocation accounting", "OK")
    else:
      printMilkvStatus("  allocation accounting", "FAIL")

    let freeA = pfree(pageA, U64(1))
    let freeB = pfree(pageB, U64(1))
    if freeA == 0 and freeB == 0:
      printMilkvStatus("  free pages", "OK")
    else:
      printMilkvStatus("  free pages", "FAIL")

    let afterFree = bitmapInfo()
    printMilkvUnsigned("  used pages after  ", afterFree.used)
    printMilkvUnsigned("  free pages after  ", afterFree.free)

    if afterFree.used == before.used and afterFree.free == before.free:
      printMilkvStatus("  free accounting", "OK")
    else:
      printMilkvStatus("  free accounting", "FAIL")


  ## Runs Phase 2 memory runtime checks and allocator smoke tests.
  proc runMilkvPhase2Checks(dtb: pointer) =
    printlnConsoleOnly("")
    printlnConsoleOnly("[milkv] phase2 memory runtime checks")
    if not validateMilkvMemoryWindow(dtb):
      printMilkvStatus("phase2 memory validation", "FAIL")
      return

    discard initMilkvPhase2Memory()
    runMilkvAllocatorSmokeTest()
    printMilkvStatus("phase2 memory runtime", "OK")


  ## Runs Phase 1 runtime probes without restoring the full QEMU boot path.
  proc runMilkvPhase1Checks(hartid: U64, dtb: pointer) =
    discard hartid
    printlnConsoleOnly("")
    printlnConsoleOnly("[milkv] phase1 runtime checks")
    checkMilkvTrapVector()
    printMilkvCsrSnapshot()
    checkMilkvTimerCall()
    printMilkvMemoryCandidate(dtb)
    runMilkvPhase2Checks(dtb)


  ## Prints the minimum Milk-V Duo 256M bring-up log and stops before QEMU-only init.
  proc milkvBringupBoot(hartid: U64, dtb: pointer) =
    printlnConsoleOnly("")
    printlnConsoleOnly("Rk-C milkv duo256m bring-up")
    printConsoleOnly("hartid = ")
    printUnsigned(hartid)
    putChar('\n')
    printBringupAddress("dtb    = ", cast[U64](dtb))
    printBringupAddress("kernel = ", cast[U64](addr kernelBaseSym))
    printBringupAddress("end    = ", cast[U64](addr kernelEndSym))
    printBringupAddress("stack  = ", cast[U64](addr stackTopSym))
    runMilkvPhase1Checks(hartid, dtb)
    enterBringupLoop()


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

    printBootMsg("  enable timer interrupt ")
    setNextTimer()
    enableTimerInterrupt()
    println("OK")

    addressInfo(hartid, dtb, memInfo)
    print("\n")

    if createKernelProcessNamed(bootTask, "boot_task") < 0:
      panic("failed to create boot task")
