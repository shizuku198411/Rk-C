## Implements system-level syscall handlers such as time, entropy, and shutdown.
import ../../../arch/riscv64/arch
import ../../../lib/calc
import ../../../lib/syscall_types
import ../../../lib/types
import ../../dev/cpu_info
import ../../dev/rtc
import ../../dev/timer
import ../../dev/klog
import ../../dev/tty
import ../../mm/usercopy
import ../../task/process
import ../../system/shutdown
import ../syscall_cap


const
  MaxEntropyBytes = U64(4096)

var
  entropyState {.volatile.}: U64 = U64(0x726b635f656e7472'u64)
  kmsgReadBuf: array[SysKmsgMax, char]


## Implements the entropy mix kernel helper.
proc entropyMix(value: U64): U64 =
  var z = value
  z = (z xor (z shr 30)) * U64(0xbf58476d1ce4e5b9'u64)
  z = (z xor (z shr 27)) * U64(0x94d049bb133111eb'u64)
  z xor (z shr 31)


## Implements the next entropy64 kernel helper.
proc nextEntropy64(): U64 =
  var pidPart = U64(0)
  if currentProc != nil:
    pidPart = U64(currentProc.pid)

  entropyState = entropyState xor arch.rdtime() xor (timerTickCount shl 32) xor
      (pidPart shl 16)
  entropyState = entropyState + U64(0x9e3779b97f4a7c15'u64)
  entropyMix(entropyState)


## Handles the ticks syscall operation.
proc syscallTicks*(): U64 =
  timerTickCount


## Handles the cpu info syscall operation.
proc syscallCpuInfo*(outInfo: U64): U64 =
  if outInfo == 0:
    return U64(-1'i64)

  let windowTotal =
    if lastCpuWindowTicks != U64(0):
      lastCpuWindowTicks
    else:
      cpuWindowTickCount
  let windowIdle =
    if lastCpuWindowTicks != U64(0):
      lastIdleWindowTicks
    else:
      idleWindowTickCount
  let windowBusy =
    if lastCpuWindowTicks != U64(0):
      lastBusyWindowTicks
    elif windowTotal >= windowIdle:
      windowTotal - windowIdle
    else:
      U64(0)
  let usage =
    if lastCpuWindowTicks != U64(0):
      lastCpuUsagePercent
    elif windowTotal == U64(0):
      U32(0)
    else:
      U32((windowBusy * U64(100)) div windowTotal)

  var info = SysCpuInfo(
    totalTicks: timerTickCount,
    windowTicks: windowTotal,
    idleTicks: windowIdle,
    busyTicks: windowBusy,
    usagePercent: usage,
  )

  if copyToUser(outInfo, addr info, U64(sizeof(SysCpuInfo))) != 0:
    return U64(-1'i64)

  0


## Handles the static cpu info syscall operation.
proc syscallCpuStaticInfo*(outInfo: U64): U64 =
  if outInfo == 0:
    return U64(-1'i64)

  var info = cpuStaticInfo()
  if copyToUser(outInfo, addr info, U64(sizeof(SysCpuStaticInfo))) != 0:
    return U64(-1'i64)

  0


## Handles the console info syscall operation.
proc syscallConsoleInfo*(outInfo: U64): U64 =
  if outInfo == 0:
    return U64(-1'i64)

  var info = ttyInfo(Tty0Id)
  if copyToUser(outInfo, addr info, U64(sizeof(SysConsoleInfo))) != 0:
    return U64(-1'i64)

  0


## Handles the kmsg syscall operation.
proc syscallKmsg*(outBuf, capacity: U64): U64 =
  if outBuf == U64(0) or capacity == U64(0) or capacity > U64(SysKmsgMax):
    return U64(-1'i64)

  let size = readKlog(cast[ptr UncheckedArray[char]](addr kmsgReadBuf[0]), capacity)
  if size == U64(0):
    return U64(0)

  if copyToUser(outBuf, addr kmsgReadBuf[0], size) != 0:
    return U64(-1'i64)

  size


## Handles the shutdown syscall operation.
proc syscallShutdown*(): U64 =
  if not canSyscallShutdown():
    return U64(-1'i64)

  U64(shutdownSystem())


## Handles the yield syscall operation.
proc syscallYield*(): U64 =
  yieldCpu()
  0


## Handles the sleep syscall operation.
proc syscallSleep*(ticks: U64): U64 =
  if ticks == 0:
    return 0

  sleepCurrentUntilTick(saturatingAddU64(timerTickCount, ticks))
  0


## Handles the get date time syscall operation.
proc syscallGetDateTime*(outDateTime: U64): U64 =
  if outDateTime == 0:
    return U64(-1'i64)

  var dt = nowDateTime()
  if copyToUser(outDateTime, addr dt, U64(sizeof(SysDateTime))) != 0:
    return U64(-1'i64)

  0


## Handles the entropy syscall operation.
proc syscallEntropy*(outBuf: U64, size: U64): U64 =
  if size == 0:
    return 0
  if outBuf == 0 or size > MaxEntropyBytes:
    return U64(-1'i64)

  var chunk: array[64, U8]
  var written = U64(0)
  while written < size:
    var chunkLen = U64(sizeof(chunk))
    if chunkLen > size - written:
      chunkLen = size - written

    var pos = U64(0)
    while pos < chunkLen:
      let value = nextEntropy64()
      var byteIndex = U64(0)
      while byteIndex < U64(8) and pos < chunkLen:
        chunk[pos] = U8((value shr (byteIndex * U64(8))) and U64(0xff))
        inc pos
        inc byteIndex

    if copyToUser(outBuf + written, addr chunk[0], chunkLen) != 0:
      return U64(-1'i64)

    written += chunkLen

  written
