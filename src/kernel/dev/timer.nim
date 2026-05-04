import ../../arch/riscv64/arch
import ../../lib/types

const
  TimerInterval* = U64(200000)

var timerTickCount* {.volatile.}: U64

proc setNextTimer*() =
  let now = arch.rdtime()
  arch.writeStimecmp(now + TimerInterval)

proc countUpTimerTick*() =
  inc timerTickCount
