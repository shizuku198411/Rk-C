import ../../../lib/syscall_types
import ../../../lib/types
import ../../dev/rtc
import ../../dev/timer
import ../../mm/usercopy
import ../../task/process


proc sbiShutdown() {.importc: "sbi_shutdown", cdecl.}


proc syscallTicks*(): U64 =
  timerTickCount


proc syscallShutdown*() =
  sbiShutdown()


proc syscallYield*(): U64 =
  yieldCpu()
  0


proc syscallSleep*(ticks: U64): U64 =
  if ticks == 0:
    return 0

  sleepCurrentUntilTick(timerTickCount + ticks)
  0


proc syscallGetDateTime*(outDateTime: U64): U64 =
  if outDateTime == 0:
    return U64(-1'i64)

  var dt = nowDateTime()
  if copyToUser(outDateTime, addr dt, U64(sizeof(SysDateTime))) != 0:
    return U64(-1'i64)

  0
