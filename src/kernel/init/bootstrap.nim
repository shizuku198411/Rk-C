## Boots the kernel, initializes subsystems, and starts initial user services.
import ../../arch/riscv64/arch
import ../../lib/calc
import ../../lib/mem
import ../../lib/types
import ../../lib/user_ids
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
