## Implements trap diagnostic syscall handlers.
import ../../../lib/syscall_types
import ../../../lib/types
import ../../mm/usercopy
import ../../trap/syscall_trace
import ../syscall_cap


const
  TraceOff = U64(0)
  TraceOn  = U64(1)
  TracePid = U64(2)
  TraceVerbose = U64(3)


var trapCount* {.volatile.}: SysTrapCount


## Handles the trap count syscall operation.
proc syscallTrapCount*(outEntries: U64): U64 =
  if outEntries == 0:
    return U64(-1'i64)

  let bytes = U64(sizeof(SysTrapCount))
  if copyToUser(outEntries, addr trapCount, bytes) != 0:
    return U64(-1'i64)
  0


## Handles the trace ctl syscall operation.
proc syscallTraceCtl*(cmd: U64, value: U64): U64 =
  if not canSyscallTraceCtl():
    return U64(-1'i64)
  
  case cmd
  of TraceOff:
    syscallTraceEnabled = false
    syscallTraceVerbose = false
    syscallTracePid = -1
    return 0
  
  of TraceOn:
    syscallTraceEnabled = true
    return 0

  of TracePid:
    syscallTraceEnabled = true
    syscallTracePid = int32(value)
    return 0

  of TraceVerbose:
    syscallTraceVerbose = value != 0
    return 0

  else:
    return U64(-1'i64)
