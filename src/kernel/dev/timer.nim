import ../../arch/riscv64/arch
import ../../lib/calc
import ../../lib/types

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


proc setNextTimer*() =
  let now = arch.rdtime()
  arch.writeStimecmp(now + TimerInterval)


proc countUpTimerTick*() =
  saturatingIncU64(timerTickCount)
  saturatingIncU64(cpuWindowTickCount)


proc countUpIdleTick*() =
  saturatingIncU64(idleTickCount)
  saturatingIncU64(idleWindowTickCount)


proc cpuWindowReady*(): bool =
  cpuWindowTickCount >= CpuUsageWindowTicks


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
