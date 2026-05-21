## Validates poll readiness for IPC, timers, pipes, and invalid fds.
import ../../lib/core/args
import ../../lib/core/io
import ../../lib/core/strutils
import ../../lib/core/syscall


var
  parsedArgs: UserArgs
  events: array[2, SysPollEvent]
  fds: array[2, I32]
  byteBuf: array[1, U8]


## Prints pollcheck usage information.
proc printUsage() =
  write("usage: pollcheck\n")


## Prints a pollcheck failure and exits.
proc fail(msg: cstring) {.noreturn.} =
  write("pollcheck: FAIL ")
  write(msg)
  write("\n")
  sysExit(1)


## Clears all reusable poll event slots.
proc resetEvents() =
  var i = 0
  while i < len(events):
    events[i] = SysPollEvent()
    inc i


## Requires one event slot to include a readiness flag.
proc expectEvent(index: U32, flag: U32, msg: cstring) =
  if (events[index].revents and flag) == 0:
    fail(msg)
  write("pollcheck: ")
  write(msg)
  write(" ok\n")


## Runs the poll behavior checks.
proc runCheck() =
  resetEvents()
  events[0].events = SysPollIpcRead
  if sysPoll(addr events[0], U64(1), U64(0)) != 0:
    fail(cstring("ipc empty"))
  write("pollcheck: ipc empty ok\n")

  resetEvents()
  events[0].events = SysPollTimer
  if sysPoll(addr events[0], U64(1), U64(2)) != 1:
    fail(cstring("timer"))
  expectEvent(U32(0), SysPollTimer, cstring("timer"))

  if sysPipe(addr fds[0]) != 0:
    fail(cstring("pipe create"))

  resetEvents()
  events[0].target = fds[0]
  events[0].events = SysPollFdRead
  if sysPoll(addr events[0], U64(1), U64(0)) != 0:
    fail(cstring("pipe read empty"))
  write("pollcheck: pipe read empty ok\n")

  resetEvents()
  events[0].target = fds[1]
  events[0].events = SysPollFdWrite
  if sysPoll(addr events[0], U64(1), U64(0)) != 1:
    fail(cstring("pipe write ready"))
  expectEvent(U32(0), SysPollFdWrite, cstring("pipe write ready"))

  byteBuf[0] = U8('x')
  if sysWriteFd(fds[1], addr byteBuf[0], U64(1)) != 1:
    fail(cstring("pipe write"))

  resetEvents()
  events[0].target = fds[0]
  events[0].events = SysPollFdRead
  if sysPoll(addr events[0], U64(1), U64(0)) != 1:
    fail(cstring("pipe read ready"))
  expectEvent(U32(0), SysPollFdRead, cstring("pipe read ready"))

  resetEvents()
  events[0].target = I32(99)
  events[0].events = SysPollFdRead
  if sysPoll(addr events[0], U64(1), U64(0)) != 1:
    fail(cstring("invalid fd"))
  expectEvent(U32(0), SysPollError, cstring("invalid fd error"))

  discard sysClose(fds[0])
  discard sysClose(fds[1])

  write("pollcheck: ok\n")
  sysExit(0)


## Parses pollcheck arguments and runs the check suite.
proc user_start*(arg: cstring) {.exportc, cdecl, noreturn.} =
  if not parseUserArgs(arg, parsedArgs):
    printUsage()
    sysExit(1)

  if parsedArgs.argc == 1 and cstringEq(argAt(parsedArgs, 0), "--help"):
    printUsage()
    sysExit(0)

  if parsedArgs.argc != 0:
    printUsage()
    sysExit(1)

  runCheck()
