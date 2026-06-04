## Runs Milk-V Phase 3 timer interrupt validation.
import ../../../arch/riscv64/arch
import ../../../lib/types
import ../../dev/console
import ../../trap/trap
import ../../../platform/milkv_duo256m/memory_layout
import ../runtime_setup
import ./shared

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
proc runMilkvPhase3Checks*() =
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
