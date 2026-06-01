## Coordinates syscall trace state and entry/exit trace output.
import ../dev/console
import ../task/process
import ../trap/trap_types
import ./syscall_trace_args
import ./syscall_trace_defs


var
  syscallTraceEnabled* = false
  syscallTraceVerbose* = false
  syscallTracePid*: int32 = -1


## Returns true when the current process should emit syscall trace output.
proc shouldTrace(): bool =
  if not syscallTraceEnabled:
    return false
  if currentProc == nil:
    return false
  if syscallTracePid >= 0 and currentProc.pid != syscallTracePid:
    return false
  true


## Emits syscall entry trace output for the current process.
proc traceSyscallEnter*(frame: ptr TrapFrame) =
  if not shouldTrace():
    return

  print("[strace] -> pid=")
  printSigned(currentProc.pid)
  print(" exe=")
  print(currentProc.exePath)
  print(" sys=")
  print(syscallName(frame.a3))
  print("#")
  printUnsigned(frame.a3)
  print("(")

  printSyscallArgs(frame, syscallTraceVerbose)
  print(")")
  putChar('\n')


## Emits syscall exit trace output for the current process.
proc traceSyscallExit*(frame: ptr TrapFrame) =
  if not shouldTrace():
    return

  print("[strace] <- pid=")
  printSigned(currentProc.pid)
  print(" sys=")
  print(syscallName(frame.a3))
  print("#")
  printUnsigned(frame.a3)
  print(" ret=")
  printPtr(frame.a0)
  putChar('\n')
