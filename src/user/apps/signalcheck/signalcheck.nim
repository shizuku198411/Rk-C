## Checks child-exit signal delivery after waiting for a child process.
import ../../../lib/syscall_types
import ../../lib/core/io
import ../../lib/core/syscall


## Prints a signalcheck failure and exits.
proc fail(msg: cstring) {.noreturn.} =
  write("signalcheck: ")
  write(msg)
  write("\n")
  sysExit(1)


## Starts a child app, waits for it, and validates the signal queue.
proc user_start*(arg: cstring) {.exportc, cdecl, noreturn.} =
  discard arg

  let child = sysExec(cstring("/bin/date"), nil, false)
  if child <= 0:
    fail(cstring("exec failed"))

  let status = sysWait(child)
  if status != 0:
    fail(cstring("wait failed"))
  write("signalcheck: child wait ok\n")

  var signal = SysSignalNone
  if sysSignalPoll(addr signal) != 0:
    fail(cstring("signal poll failed"))
  if signal != SysSignalChildExited:
    fail(cstring("child signal missing"))
  write("signalcheck: child_exited signal ok\n")

  signal = SysSignalNone
  if sysSignalPoll(addr signal) != 0:
    fail(cstring("second signal poll failed"))
  if signal != SysSignalNone:
    fail(cstring("signal queue not empty"))
  write("signalcheck: empty signal queue ok\n")
  write("signalcheck: ok\n")

  sysExit(0)
