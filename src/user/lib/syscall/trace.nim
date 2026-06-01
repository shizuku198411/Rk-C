## Provides wrappers for syscall tracing controls.
import ./base
import ../../../lib/syscall_ids

const
  TraceOff* = U64(0)
  TraceOn*  = U64(1)
  TracePid* = U64(2)
  TraceVerbose* = U64(3)


## Invokes the trace ctl syscall wrapper.
proc sysTraceCtl*(cmd: U64, value: U64): I32 =
  I32(rawSyscall3(SysTraceCtl, cmd, value, 0))
