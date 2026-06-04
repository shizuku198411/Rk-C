## Coordinates isolated Milk-V Duo 256M bring-up validation phases.
import ../../lib/types
import ../dev/console
import ./runtime_setup
import ./milkv_bringup/shared
import ./milkv_bringup/phase2_memory
import ./milkv_bringup/phase3_timer
import ./milkv_bringup/phase4_dtb
import ./milkv_bringup/phase6_runtime
import ./milkv_bringup/phase7_devices
import ./milkv_bringup/phase8_appfs


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
proc milkvBringupBoot*(hartid: U64, dtb: pointer) =
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
