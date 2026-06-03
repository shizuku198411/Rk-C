## Provides Milk-V Duo 256M timer programming through SBI.
import ../../lib/types


## Imports the SBI set_timer routine.
proc sbiSetTimer(value: U64) {.importc: "sbi_set_timer", cdecl.}


## Programs the next supervisor timer interrupt.
proc setNextTimer*(next: U64) =
  sbiSetTimer(next)
