import ../../../lib/syscall_types
import ../../../lib/types
import ../../dev/rtc
import ../../dev/timer

proc sbiShutdown() {.importc: "sbi_shutdown", cdecl.}

proc syscallTicks*(): U64 =
  timerTickCount

proc syscallShutdown*() =
  sbiShutdown()

proc syscallGetDateTime*(outDateTime: U64): U64 =
  if outDateTime == 0:
    return U64(-1'i64)

  cast[ptr SysDateTime](outDateTime)[] = nowDateTime()
  0
