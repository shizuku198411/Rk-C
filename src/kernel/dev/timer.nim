## Tracks timer ticks, idle ticks, and CPU accounting windows.
import ../../arch/riscv64/arch
import ../../lib/calc
import ../../lib/types

when defined(platformMilkVDuo256m):
  proc sbiSetTimer(value: U64) {.importc: "sbi_set_timer", cdecl.}

const
  TimerInterval* = U64(200000)
  CpuUsageWindowTicks* = U64(100)

var
  timerTickCount* {.volatile.}: U64
  idleTickCount* {.volatile.}: U64
  cpuWindowTickCount* {.volatile.}: U64
  idleWindowTickCount* {.volatile.}: U64
  lastCpuWindowTicks* {.volatile.}: U64
  lastIdleWindowTicks* {.volatile.}: U64
  lastBusyWindowTicks* {.volatile.}: U64
  lastCpuUsagePercent* {.volatile.}: U32


## Sets next timer.
proc setNextTimer*() =
  let now = arch.rdtime()
  when defined(platformMilkVDuo256m):
    sbiSetTimer(now + TimerInterval)
  else:
    arch.writeStimecmp(now + TimerInterval)


## Implements the count up timer tick kernel helper.
proc countUpTimerTick*() =
  saturatingIncU64(timerTickCount)
  saturatingIncU64(cpuWindowTickCount)


## Implements the count up idle tick kernel helper.
proc countUpIdleTick*() =
  saturatingIncU64(idleTickCount)
  saturatingIncU64(idleWindowTickCount)


## Implements the cpu window ready kernel helper.
proc cpuWindowReady*(): bool =
  cpuWindowTickCount >= CpuUsageWindowTicks


## Implements the snapshot cpu window kernel helper.
proc snapshotCpuWindow*() =
  let total = cpuWindowTickCount
  let idle = idleWindowTickCount
  let busy =
    if total >= idle:
      total - idle
    else:
      U64(0)

  lastCpuWindowTicks = total
  lastIdleWindowTicks = idle
  lastBusyWindowTicks = busy
  lastCpuUsagePercent =
    if total == U64(0):
      U32(0)
    else:
      U32((busy * U64(100)) div total)

  cpuWindowTickCount = U64(0)
  idleWindowTickCount = U64(0)
