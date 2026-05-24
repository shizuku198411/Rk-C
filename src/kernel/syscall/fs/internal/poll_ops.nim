## Evaluates descriptor readiness and implements poll waits.

## Implements the fd read ready kernel helper.
proc fdReadReady(fd: I32): bool =
  if not validFd(fd):
    return false

  let entry = addr currentProc.files.entries[U32(fd)]
  if (entry.flags and SysOpenRead) == 0:
    return false

  if entry.kind == SysFdKindPipe:
    return pipeReadable(entry.pipeId)
  if entry.kind == SysFdKindFile:
    return true

  false


## Implements the fd write ready kernel helper.
proc fdWriteReady(fd: I32): bool =
  if not validFd(fd):
    return false

  let entry = addr currentProc.files.entries[U32(fd)]
  if (entry.flags and SysOpenWrite) == 0:
    return false

  if entry.kind == SysFdKindPipe:
    return pipeWritable(entry.pipeId)
  if entry.kind == SysFdKindStdout or entry.kind == SysFdKindStderr or
      entry.kind == SysFdKindConsole or entry.kind == SysFdKindFile:
    return true

  false


## Implements the evaluate poll events kernel helper.
proc evaluatePollEvents(count: U64, timedOut: bool): I32 =
  var ready = I32(0)
  var i = U32(0)
  while U64(i) < count:
    var revents = U32(0)
    let requested = pollEvents[i].events
    let target = pollEvents[i].target

    if (requested and SysPollFdRead) != 0:
      if not validFd(target):
        revents = revents or SysPollError
      elif fdReadReady(target):
        revents = revents or SysPollFdRead

    if (requested and SysPollFdWrite) != 0:
      if not validFd(target):
        revents = revents or SysPollError
      elif fdWriteReady(target):
        revents = revents or SysPollFdWrite

    if (requested and SysPollIpcRead) != 0:
      if currentProc != nil and currentProc.ipc.count > 0:
        revents = revents or SysPollIpcRead

    if (requested and SysPollPidExit) != 0:
      let p = findProcessByPid(target)
      if p == nil:
        revents = revents or SysPollError
      elif p.state == procZombie:
        revents = revents or SysPollPidExit

    if (requested and SysPollTimer) != 0 and timedOut:
      revents = revents or SysPollTimer

    if (requested and not KnownPollEvents) != 0:
      revents = revents or SysPollError

    pollEvents[i].revents = revents
    if revents != 0:
      inc ready
    inc i

  ready


## Copies poll events to user.
proc copyPollEventsToUser(eventsVal, count: U64): bool =
  let bytes = count * U64(sizeof(SysPollEvent))
  copyToUser(eventsVal, addr pollEvents[0], bytes) == 0


## Handles the poll syscall operation.
proc syscallPoll*(eventsVal, count, timeoutTicks: U64): U64 =
  if currentProc == nil or eventsVal == 0 or count == 0 or count > U64(SysPollMaxEvents):
    return U64(-1'i64)

  let bytes = count * U64(sizeof(SysPollEvent))
  if copyFromUser(addr pollEvents[0], eventsVal, bytes) != 0:
    return U64(-1'i64)

  var ready = evaluatePollEvents(count, false)
  if ready > 0 or timeoutTicks == 0:
    if not copyPollEventsToUser(eventsVal, count):
      return U64(-1'i64)
    return U64(ready)

  let deadline = saturatingAddU64(timerTickCount, timeoutTicks)
  while true:
    sleepCurrentForPoll(deadline)
    let timedOut = timerTickCount >= deadline
    ready = evaluatePollEvents(count, timedOut)
    if ready > 0 or timedOut:
      if not copyPollEventsToUser(eventsVal, count):
        return U64(-1'i64)
      return U64(ready)
