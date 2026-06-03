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
import ../../platform/toolchain_policy

when defined(platformMilkVDuo256m) and defined(milkvBringup):
  import ../../platform/milkv_duo256m/memory_layout

when defined(milkvBringup):
  import ../../lib/syscall_ids
  import ../lib/fdt
  import ../dev/uart16550
  import ../dev/sd/sdhci
  import ../fs/blockdev
  import ../fs/partition
  import ../trap/trap

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
  if not toolchain_policy.installToolchainStdlibOnBoot():
    printBootMsg(" optional toolchain standard library ... SKIP\n")
    return

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
    MilkvEmbeddedUserMessageLen = U64(27)

  var
    milkvBssProbe: U64
    milkvSupervisorStarted: bool
    milkvEmbeddedUserDone: bool


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


  ## Prints a fixed-size NUL-terminated string with a Milk-V label.
  proc printMilkvFixedString(label: cstring, value: openArray[char]) =
    printMilkvPrefix()
    printConsoleOnly(label)
    printConsoleOnly(" = ")

    var i = 0
    while i < value.len and value[i] != '\0':
      putChar(value[i])
      inc i

    if i == 0:
      printConsoleOnly("(empty)")

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


  ## Arms the Milk-V supervisor timer through OpenSBI.
  proc armMilkvTimer(): U64 =
    let now = arch.rdtime()
    let next = now + MilkvTimerInterruptDelta
    sbiSetTimer(next)
    next


  ## Enables supervisor timer interrupts for Milk-V bring-up.
  proc enableMilkvTimerInterrupts() =
    arch.writeSie(arch.readSie() or SieStie)
    arch.writeSstatus((arch.readSstatus() or SstatusSie) and not SstatusSum)


  ## Waits for a small number of Milk-V timer interrupts.
  proc waitForMilkvTimerInterrupts(targetCount: U64): bool =
    let timeout = arch.rdtime() + MilkvTimerInterruptDelta * U64(12)
    var lastSeen = milkvTimerInterruptCount

    printMilkvPrefix()
    printlnConsoleOnly("timer interrupts:")

    while arch.rdtime() < timeout:
      if milkvTimerInterruptCount != lastSeen:
        lastSeen = milkvTimerInterruptCount
        printMilkvUnsigned("  count", lastSeen)

      if milkvTimerInterruptCount >= targetCount:
        return true

      arch.wfi()

    false


  ## Runs Phase 3 timer interrupt checks while still using SBI console output.
  proc runMilkvPhase3Checks() =
    printlnConsoleOnly("")
    printlnConsoleOnly("[milkv] phase3 timer/trap runtime checks")

    setTrapVector()
    milkvTimerInterruptCount = U64(0)
    milkvLastTimerScause = U64(0)
    milkvLastTimerSepc = U64(0)

    printMilkvPrefix()
    printlnConsoleOnly("interrupt setup:")
    printMilkvHex("  stvec     ", arch.readStvec())
    printMilkvHex("  sscratch  ", arch.readSscratch())
    printMilkvHex("  before sie", arch.readSie())
    printMilkvHex("  before sstatus", arch.readSstatus())

    let next = armMilkvTimer()
    printMilkvHex("  timer now ", arch.rdtime())
    printMilkvHex("  timer next", next)

    enableMilkvTimerInterrupts()
    printMilkvHex("  after sie ", arch.readSie())
    printMilkvHex("  after sstatus", arch.readSstatus())

    let timerOk = waitForMilkvTimerInterrupts(U64(3))
    if timerOk:
      printMilkvStatus("timer interrupt", "OK")
      printMilkvHex("  last scause", milkvLastTimerScause)
      printMilkvHex("  last sepc  ", milkvLastTimerSepc)
    else:
      printMilkvStatus("timer interrupt", "FAIL")
      printMilkvHex("  last scause", milkvLastTimerScause)
      printMilkvHex("  last sepc  ", milkvLastTimerSepc)

    printMilkvPrefix()
    printlnConsoleOnly("console backend = sbi")
    printMilkvHex("  uart0 candidate", MilkvUart0Base)
    if timerOk:
      printMilkvStatus("phase3 timer/trap runtime", "OK")
    else:
      printMilkvStatus("phase3 timer/trap runtime", "FAIL")


  ## Prints one parsed FDT region.
  proc printMilkvFdtRegion(prefix: cstring, region: FdtRegion) =
    printMilkvPrefix()
    printConsoleOnly(prefix)
    printConsoleOnly(" ")
    var i = 0
    while i < region.name.len and region.name[i] != '\0':
      putChar(region.name[i])
      inc i
    printConsoleOnly(" base=")
    printPtr(region.base)
    printConsoleOnly(" size=")
    printPtr(region.size)
    putChar('\n')


  ## Prints FDT parser header diagnostics.
  proc printMilkvFdtHeader(scan: FdtScanResult) =
    printMilkvPrefix()
    printlnConsoleOnly("fdt header:")
    printMilkvHex("  magic     ", U64(scan.header.magic))
    printMilkvHex("  totalsize ", scan.header.totalSize)
    printMilkvHex("  struct off", scan.header.offDtStruct)
    printMilkvHex("  strings off", scan.header.offDtStrings)
    printMilkvHex("  reserve off", scan.header.offMemRsvmap)
    printMilkvHex("  struct size", scan.header.sizeDtStruct)
    printMilkvHex("  strings size", scan.header.sizeDtStrings)
    printMilkvUnsigned("  version   ", U64(scan.header.version))
    printMilkvUnsigned("  last comp ", U64(scan.header.lastCompVersion))


  ## Prints FDT memory and reserved memory diagnostics.
  proc printMilkvFdtMemory(scan: FdtScanResult) =
    printMilkvPrefix()
    printlnConsoleOnly("memory:")
    printMilkvUnsigned("  address-cells", U64(scan.addressCells))
    printMilkvUnsigned("  size-cells   ", U64(scan.sizeCells))
    if scan.memoryRegion.valid:
      printMilkvFdtRegion("  memory", scan.memoryRegion)
      printMilkvStatus("memory range", "OK")
    else:
      printMilkvStatus("memory range", "WARN")

    printMilkvPrefix()
    printlnConsoleOnly("fdt reserve map:")
    if scan.reserveMapCount == U64(0):
      printMilkvStatus("  reserve map", "empty")
    else:
      var i = U64(0)
      while i < scan.reserveMapCount:
        printMilkvFdtRegion("  reserve", scan.reserveMap[i])
        inc i

    printMilkvPrefix()
    printlnConsoleOnly("reserved-memory:")
    if scan.reservedMemoryCount == U64(0):
      printMilkvStatus("  reserved-memory", "WARN")
    else:
      var i = U64(0)
      while i < scan.reservedMemoryCount:
        printMilkvFdtRegion("  region", scan.reservedMemory[i])
        inc i


  ## Prints FDT device candidate diagnostics.
  proc printMilkvDeviceCandidate(label: cstring, found: bool) =
    if found:
      printMilkvStatus(label, "FOUND")
    else:
      printMilkvStatus(label, "MISSING")


  ## Returns whether one reserved-memory range matches the known ION base.
  proc fdtHasKnownIonRegion(scan: FdtScanResult): bool =
    var i = U64(0)
    while i < scan.reservedMemoryCount:
      if scan.reservedMemory[i].valid and scan.reservedMemory[i].base == MilkvReservedIonStart:
        return true
      inc i

    false


  ## Prints DTB values against Milk-V fixed fallback values.
  proc printMilkvPlatformCompare(dtb: pointer, scan: FdtScanResult) =
    printMilkvPrefix()
    printlnConsoleOnly("platform compare:")

    if cast[U64](dtb) == MilkvKnownFdtAddr:
      printMilkvStatus("  fdt pointer", "OK")
    else:
      printMilkvStatus("  fdt pointer", "WARN")

    if scan.uart0Found:
      printMilkvStatus("  uart0 base", "OK")
    else:
      printMilkvStatus("  uart0 base", "WARN")

    if fdtHasKnownIonRegion(scan):
      printMilkvStatus("  ion base", "OK")
    else:
      printMilkvStatus("  ion base", "WARN")


  ## Runs Phase 4 FDT/DTB parser checks.
  proc runMilkvPhase4Checks(dtb: pointer) =
    printlnConsoleOnly("")
    printlnConsoleOnly("[milkv] phase4 dtb runtime checks")

    let scan = fdtScanBasic(dtb)
    printMilkvFdtHeader(scan)

    if not scan.header.valid:
      printMilkvStatus("fdt header", "FAIL")
      printMilkvStatus("platform fallback", "OK")
      return

    printMilkvStatus("fdt header", "OK")
    if scan.scanOk:
      printMilkvStatus("fdt structure scan", "OK")
    else:
      printMilkvStatus("fdt structure scan", "WARN")

    printMilkvPrefix()
    printlnConsoleOnly("chosen:")
    printMilkvFixedString("  stdout-path", scan.stdoutPath)

    printMilkvFdtMemory(scan)

    printMilkvPrefix()
    printlnConsoleOnly("device candidates:")
    printMilkvDeviceCandidate("  uart0 serial@4140000", scan.uart0Found)
    printMilkvDeviceCandidate("  plic interrupt-controller@70000000", scan.plicFound)
    printMilkvDeviceCandidate("  clint", scan.clintFound)
    printMilkvDeviceCandidate("  sd cv-sd@4310000", scan.sdFound)
    printMilkvDeviceCandidate("  ethernet@4070000", scan.ethernetFound)
    printMilkvPlatformCompare(dtb, scan)
    printMilkvStatus("phase4 dtb runtime", "OK")


  ## Reads a little-endian U32 from a byte buffer.
  proc milkvReadLe32(buf: ptr UncheckedArray[U8], offset: U64): U32 =
    U32(buf[offset]) or
      (U32(buf[offset + U64(1)]) shl 8) or
      (U32(buf[offset + U64(2)]) shl 16) or
      (U32(buf[offset + U64(3)]) shl 24)


  ## Prints a fixed number of bytes from a buffer as hexadecimal.
  proc printMilkvBytes(label: cstring, buf: ptr UncheckedArray[U8], count: U64) =
    printMilkvPrefix()
    printConsoleOnly(label)
    printConsoleOnly(" =")

    var i = U64(0)
    while i < count:
      putChar(' ')
      let value = U64(buf[i])
      if value < U64(0x10):
        putChar('0')
      printHex(value)
      inc i

    putChar('\n')


  ## Prints one MBR partition entry from an SD card sector.
  proc printMilkvPartitionEntry(index: U64, buf: ptr UncheckedArray[U8]) =
    let off = U64(0x1be) + index * U64(16)
    let partType = buf[off + U64(4)]
    let startLba = milkvReadLe32(buf, off + U64(8))
    let sectors = milkvReadLe32(buf, off + U64(12))

    printMilkvPrefix()
    printConsoleOnly("  partition ")
    printUnsigned(index + U64(1))
    printConsoleOnly(": type=")
    printHex(U64(partType))
    printConsoleOnly(" start=")
    printUnsigned(U64(startLba))
    printConsoleOnly(" sectors=")
    printUnsigned(U64(sectors))
    putChar('\n')


  ## Runs a direct UART0 MMIO probe without changing the global console backend.
  proc runMilkvPhase7UartChecks(): bool =
    let uart = Uart16550(base: MilkvUart0Base, regShift: U8(2), regWidth: U8(4))
    printMilkvPrefix()
    printlnConsoleOnly("uart0:")
    printMilkvHex("  base", MilkvUart0Base)
    printMilkvUnsigned("  reg shift", U64(uart.regShift))
    printMilkvUnsigned("  reg width", U64(uart.regWidth))
    printMilkvHex("  lsr", U64(uartRead(uart, U64(5))))

    if not uart16550Probe(uart):
      printMilkvStatus("uart0 probe", "FAIL")
      return false

    printMilkvStatus("uart0 probe", "OK")
    printMilkvPrefix()
    printConsoleOnly("  direct uart write: ")
    discard uart16550PutChar(uart, 'O')
    discard uart16550PutChar(uart, 'K')
    discard uart16550PutChar(uart, '\n')
    true


  ## Runs a direct SDHCI probe and attempts to read sector zero from the SD card.
  proc runMilkvPhase7SdChecks(): bool =
    var sector: array[512, U8]
    printMilkvPrefix()
    printlnConsoleOnly("sdhci:")
    printMilkvHex("  base", MilkvSdBase)

    let probe = probeSdhci(MilkvSdBase)
    printMilkvHex("  host version", U64(probe.hostVersion))
    printMilkvHex("  present state", U64(probe.presentState))
    printMilkvHex("  capabilities", probe.capabilities)
    printMilkvHex("  clock control", U64(probe.clockControl))
    printMilkvHex("  power control", U64(probe.powerControl))
    printMilkvStatus("sdhci probe", "OK")

    let read = readLba0(MilkvSdBase, addr sector[0])
    printMilkvUnsigned("  read stage", U64(ord(read.stage)))
    printMilkvHex("  int status", U64(read.intStatus))
    printMilkvHex("  present state", U64(read.presentState))
    printMilkvUnsigned("  words read", read.wordsRead)

    if not read.ok:
      printMilkvStatus("sd lba0 read", "FAIL")
      return false

    let bytes = cast[ptr UncheckedArray[U8]](addr sector[0])
    printMilkvBytes("  mbr first bytes", bytes, U64(16))
    let signature = U16(bytes[U64(510)]) or (U16(bytes[U64(511)]) shl 8)
    if signature == U16(0xaa55):
      printMilkvStatus("mbr signature", "OK")
      var i = U64(0)
      while i < U64(4):
        printMilkvPartitionEntry(i, bytes)
        inc i
      return true

    printMilkvStatus("mbr signature", "WARN")
    true


  ## Runs Phase 7 UART and SD card driver checks before entering the scheduled runtime.
  proc runMilkvPhase7Checks() =
    printlnConsoleOnly("")
    printlnConsoleOnly("[milkv] phase7 uart/sd driver checks")

    let uartOk = runMilkvPhase7UartChecks()
    let sdOk = runMilkvPhase7SdChecks()
    if uartOk and sdOk:
      printMilkvStatus("phase7 uart/sd drivers", "OK")
    else:
      printMilkvStatus("phase7 uart/sd drivers", "FAIL")


  ## Prints a Milk-V partition record.
  proc printMilkvPartition(label: cstring, part: BlockPartition) =
    printMilkvPrefix()
    printConsoleOnly(label)
    printConsoleOnly(": type=")
    printHex(U64(part.typ))
    printConsoleOnly(" start=")
    printUnsigned(part.startBlock)
    printConsoleOnly(" blocks=")
    printUnsigned(part.blockCount)
    putChar('\n')


  ## Runs Phase 8A block/appfs diagnostics without starting the full service tree.
  proc runMilkvPhase8AppfsChecks() =
    printlnConsoleOnly("")
    printlnConsoleOnly("[milkv] phase8 appfs bootstrap checks")

    blockdevInit()

    var part: BlockPartition
    if not readMbrPartition(MilkvAppfsPartitionIndex, part):
      printMilkvStatus("appfs partition", "FAIL")
      return

    printMilkvPartition("  selected partition", part)
    if not blockdevSetLogicalRange(part.startBlock, part.blockCount):
      printMilkvStatus("logical block range", "FAIL")
      return

    fsSetAppfsBaseBlock(MilkvAppfsLocalStartBlock)
    printMilkvHex("  logical base block", blockdevBaseOffset())
    printMilkvHex("  appfs local block", fsAppfsBaseBlock())

    if fsLoadAppfsOnly() != 0:
      printMilkvStatus("appfs load", "FAIL")
      return

    printMilkvStatus("appfs load", "OK")
    printMilkvUnsigned("  appfs entries", U64(fsAppfsEntryCount()))

    let svcmgtdSize = fsAppfsFileSize("/bin/svcmgtd")
    let loginSize = fsAppfsFileSize("/bin/login")
    let shellSize = fsAppfsFileSize("/bin/shell")
    printMilkvUnsigned("  /bin/svcmgtd size", U64(if svcmgtdSize < 0: 0 else: svcmgtdSize))
    printMilkvUnsigned("  /bin/login size", U64(if loginSize < 0: 0 else: loginSize))
    printMilkvUnsigned("  /bin/shell size", U64(if shellSize < 0: 0 else: shellSize))

    if svcmgtdSize >= 0 and loginSize >= 0 and shellSize >= 0:
      printMilkvStatus("appfs lookup", "OK")
      printMilkvStatus("phase8 appfs bootstrap", "OK")
    else:
      printMilkvStatus("appfs lookup", "FAIL")
      printMilkvStatus("phase8 appfs bootstrap", "FAIL")


  ## Checks BSS and current stack placement before restoring runtime state.
  proc runMilkvPhase6BssStackChecks(): bool =
    var stackProbe: U64
    let stackAddr = cast[U64](addr stackProbe)
    let stackBottom = cast[U64](addr stackBottomSym)
    let stackTop = cast[U64](addr stackTopSym)
    var ok = true

    if milkvBssProbe == U64(0):
      printMilkvStatus("bss zero", "OK")
    else:
      printMilkvStatus("bss zero", "FAIL")
      ok = false

    if stackAddr >= stackBottom and stackAddr < stackTop:
      printMilkvStatus("stack range", "OK")
    else:
      printMilkvStatus("stack range", "FAIL")
      ok = false

    printMilkvHex("  stack probe", stackAddr)
    printMilkvStatus("panic diagnostics", "READY")
    ok


  ## Runs allocator checks after earlier smoke tests have completed.
  proc runMilkvPhase6AllocatorRuntimeCheck(): bool =
    let before = bitmapInfo()
    printMilkvPrefix()
    printlnConsoleOnly("allocator runtime:")
    printMilkvUnsigned("  total pages", before.total)
    printMilkvUnsigned("  used pages ", before.used)
    printMilkvUnsigned("  free pages ", before.free)

    let pageCount = U64(4)
    let pages = palloc(pageCount)
    if pages == NilPAddr:
      printMilkvStatus("allocator runtime", "FAIL")
      return false

    let afterAlloc = bitmapInfo()
    discard pfree(pages, pageCount)
    let afterFree = bitmapInfo()
    if afterAlloc.used == before.used + pageCount and
        afterFree.used == before.used and afterFree.free == before.free:
      printMilkvStatus("allocator runtime", "OK")
      return true

    printMilkvStatus("allocator runtime", "FAIL")
    false


  ## Enables the shared kernel Sv39 mapping for Milk-V runtime restore checks.
  proc runMilkvPhase6PagingCheck(): bool =
    printMilkvPrefix()
    printlnConsoleOnly("paging:")
    let before = arch.readSatp()
    kernelRootPageTable = createKernelMappedPageTable()
    if kernelRootPageTable == nil:
      printMilkvStatus("sv39 identity map", "FAIL")
      return false

    setKernelPageTable(kernelRootPageTable)
    let satp = makeSatp(cast[PAddr](kernelRootPageTable))
    printMilkvHex("  root page table", cast[U64](kernelRootPageTable))
    printMilkvHex("  satp before", before)
    paging.flushTlb()
    arch.writeSatp(satp)
    paging.flushTlb()
    printMilkvHex("  satp after ", arch.readSatp())

    if arch.readSatp() == satp and arch.readSatp() != U64(0):
      printMilkvStatus("sv39 identity map", "OK")
      return true

    printMilkvStatus("sv39 identity map", "FAIL")
    false


  ## Writes one U32 instruction into an embedded user text page.
  proc writeMilkvUserInsn(text: ptr UncheckedArray[U32], index: U64, value: U32) =
    text[index] = value


  ## Encodes one RISC-V addi instruction with a small positive immediate.
  proc encodeMilkvAddi(rd, rs1: U32, imm: U32): U32 =
    ((imm and U32(0xfff)) shl 20) or
      ((rs1 and U32(0x1f)) shl 15) or
      ((rd and U32(0x1f)) shl 7) or
      U32(0x13)


  ## Copies the embedded user task message into its rodata page.
  proc writeMilkvUserMessage(rodata: ptr UncheckedArray[char]) =
    let msg = cstring"hello from milkv user task\n"
    var i = U64(0)
    while i < MilkvEmbeddedUserMessageLen:
      rodata[i] = msg[i]
      inc i
    rodata[i] = '\0'


  ## Creates a tiny U-mode program that writes to stdout and exits.
  proc createMilkvEmbeddedUserTask(): int32 =
    let p = allocUserProcessFromParent(currentProc)
    if p == nil:
      return -1

    let root = createKernelMappedPageTable()
    if root == nil:
      discardProcess(p)
      return -1

    let textPa = palloc(U64(1))
    let rodataPa = palloc(U64(1))
    let stackPa = palloc(U64(1))
    if textPa == NilPAddr or rodataPa == NilPAddr or stackPa == NilPAddr:
      if textPa != NilPAddr:
        discard pfree(textPa, U64(1))
      if rodataPa != NilPAddr:
        discard pfree(rodataPa, U64(1))
      if stackPa != NilPAddr:
        discard pfree(stackPa, U64(1))
      freePageTablePages(root)
      discardProcess(p)
      return -1

    zeroMem(cast[pointer](textPa), PageSize)
    zeroMem(cast[pointer](rodataPa), PageSize)
    zeroMem(cast[pointer](stackPa), PageSize)

    let text = cast[ptr UncheckedArray[U32]](textPa)
    writeMilkvUserInsn(text, U64(0), U32(0x01201537)) # lui a0, 0x1201
    writeMilkvUserInsn(text, U64(1), encodeMilkvAddi(U32(11), U32(0), U32(MilkvEmbeddedUserMessageLen)))
    writeMilkvUserInsn(text, U64(2), encodeMilkvAddi(U32(13), U32(0), U32(SysWrite)))
    writeMilkvUserInsn(text, U64(3), U32(0x00000073)) # ecall
    writeMilkvUserInsn(text, U64(4), encodeMilkvAddi(U32(10), U32(0), U32(0)))
    writeMilkvUserInsn(text, U64(5), encodeMilkvAddi(U32(13), U32(0), U32(SysExit)))
    writeMilkvUserInsn(text, U64(6), U32(0x00000073)) # ecall
    writeMilkvUserInsn(text, U64(7), U32(0x00100073)) # ebreak if exit fails
    writeMilkvUserMessage(cast[ptr UncheckedArray[char]](rodataPa))

    let textVa = AppBase
    let rodataVa = AppBase + PageSize
    let stackTop = AppStackTop
    let stackVa = stackTop - PageSize
    if mapPage(root, textVa, textPa, PteR or PteX or PteU) != 0 or
        mapPage(root, rodataVa, rodataPa, PteR or PteU) != 0 or
        mapPage(root, stackVa, stackPa, PteR or PteW or PteU) != 0:
      freePageTablePages(root)
      discardProcess(p)
      return -1

    configureUserProcess(
      p,
      root,
      cstring"milkv_embedded_user",
      AppBase,
      textVa,
      stackTop,
      stackTop,
      U64(2),
      U64(1),
    )
    setUserRkxMap(p, textVa, PageSize, rodataVa, PageSize, U64(0), U64(0), U64(0), U64(0))
    p.pid


  ## Waits for the embedded user task to exit and reports its status.
  proc waitForMilkvEmbeddedUserTask(pid: int32): bool =
    var loops = U64(0)
    var target = findProcessByPid(pid)
    while target != nil and target.state != procZombie and loops < U64(8):
      yieldCpu()
      target = findProcessByPid(pid)
      inc loops

    if target == nil or target.state != procZombie:
      printMilkvStatus("syscall exit", "FAIL")
      return false

    printMilkvUnsigned("  user exit status", target.exitStatus)
    let ok = target.exitStatus == U64(0)
    discardProcess(target)
    if ok:
      printMilkvStatus("syscall exit", "OK")
    else:
      printMilkvStatus("syscall exit", "FAIL")

    ok


  ## Runs inside the first scheduled kernel process for Phase 6 runtime checks.
  proc milkvPhase6SupervisorTask() {.cdecl.} =
    milkvSupervisorStarted = true
    printMilkvStatus("context switch", "OK")

    let start = milkvTimerInterruptCount
    while milkvTimerInterruptCount < start + U64(2):
      arch.wfi()
    printMilkvUnsigned("  timer count", milkvTimerInterruptCount)
    printMilkvStatus("scheduler timer source", "OK")

    let pid = createMilkvEmbeddedUserTask()
    if pid < 0:
      printMilkvStatus("embedded user task", "FAIL")
      enterBringupLoop()

    printMilkvUnsigned("  user pid", U64(pid))
    printMilkvStatus("embedded user task", "OK")
    if waitForMilkvEmbeddedUserTask(pid):
      printMilkvStatus("syscall write", "OK")
      milkvEmbeddedUserDone = true
      printMilkvStatus("phase6 runtime restore", "OK")
    else:
      printMilkvStatus("phase6 runtime restore", "FAIL")

    enterBringupLoop()


  ## Restores core Rk-C runtime pieces far enough to run a tiny user process.
  proc runMilkvPhase6Checks() =
    printlnConsoleOnly("")
    printlnConsoleOnly("[milkv] phase6 runtime restore checks")
    printMilkvStatus("qemu drivers", "SKIP")
    printMilkvStatus("runtime mode", "minimal")

    if not runMilkvPhase6BssStackChecks():
      printMilkvStatus("phase6 runtime restore", "FAIL")
      return

    if not runMilkvPhase6AllocatorRuntimeCheck():
      printMilkvStatus("phase6 runtime restore", "FAIL")
      return

    processInit()
    let idle = findProcessByPid(1)
    if idle != nil and idle.state == procRunnable:
      printMilkvStatus("process table", "OK")
      printMilkvUnsigned("  idle task pid", U64(idle.pid))
    else:
      printMilkvStatus("process table", "FAIL")
      printMilkvStatus("phase6 runtime restore", "FAIL")
      return

    if not runMilkvPhase6PagingCheck():
      printMilkvStatus("phase6 runtime restore", "FAIL")
      return

    let supervisorPid = createKernelProcessNamed(milkvPhase6SupervisorTask, "milkv_phase6")
    if supervisorPid < 0:
      printMilkvStatus("phase6 supervisor", "FAIL")
      printMilkvStatus("phase6 runtime restore", "FAIL")
      return

    printMilkvUnsigned("  supervisor pid", U64(supervisorPid))
    printMilkvStatus("phase6 supervisor", "OK")
    schedule()

    if not milkvSupervisorStarted or not milkvEmbeddedUserDone:
      printMilkvStatus("phase6 scheduler return", "WARN")


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
    runMilkvPhase3Checks()
    runMilkvPhase4Checks(dtb)
    runMilkvPhase7Checks()
    runMilkvPhase8AppfsChecks()
    runMilkvPhase6Checks()


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
