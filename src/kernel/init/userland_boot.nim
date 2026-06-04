## Starts initial userspace services, login, and optional hosted tooling.
import ../../generated/version
import ../../lib/calc
import ../../lib/types
import ../../lib/user_ids
import ../../platform/status_led
import ../dev/console
import ../dev/timer
import ../fs/fs
import ../service/registry
import ../task/exec
import ../task/process


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



## Implements the kernel banner kernel helper.
proc printBannerVersionLine() =
  printConsoleOnly("  |   version: ")
  printConsoleOnly(cstring(RkcVersion))

  var spaces = 40 - 11 - RkcVersion.len
  while spaces > 0:
    putChar(' ')
    dec spaces

  printlnConsoleOnly("|")


## Implements the kernel banner kernel helper.
proc kernelBanner() =
  putChar('\n')
  printlnConsoleOnly("  +-----------------------------------------+")
  printlnConsoleOnly("  |            Welcome to Rk-C!             |")
  printlnConsoleOnly("  |-----------------------------------------|")
  printlnConsoleOnly("  |   microkernel-style system on RISC-V    |")
  printBannerVersionLine()
  printlnConsoleOnly("  +-----------------------------------------+")
  printConsoleOnly("\n")


## Waits for for initial services.
proc waitForInitialServices() =
  let deadline = saturatingAddU64(timerTickCount, ServiceWaitTimeoutTicks)

  while not allServicesReady():
    if timerTickCount >= deadline:
      if not requiredServicesReady():
        printBootMsg("  required service wait timeout\n")
        panic("required services did not become ready")

      printBootMsg(" optional service wait timeout; degraded boot\n")
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
proc bootTask*() {.cdecl.} =
  if createServiceManagerUserProcess() < 0:
    panic("failed to create service manager")

  waitForInitialServices()

  maybeInstallToolchainStdlib()

  if createLoginUserProcess() < 0:
    panic("failed to create login")

  if not status_led.setStatusLed(true):
    printBootMsg("  status LED ... FAIL\n")

  if currentProc != nil:
    currentProc.detached = true

  kernelBanner()
