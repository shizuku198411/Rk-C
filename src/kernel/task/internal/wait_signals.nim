## Coordinates sleeping, waking, exit delivery, signals, and reschedule requests.

## Marks a timer/poll waiter as woken.
proc wakeTimerDeadlineProcess(p: ptr Process) =
  if p == nil:
    return
  clearWaitNoTimerRecompute(p)
  p.state = procRunnable


## Implements the request resched kernel helper.
proc requestResched*() =
  needResched = true


## Prints process state.
proc printProcessState*(state: ProcessState) =
  case state
  of procUnused:
    print("unused  ")
  of procRunnable:
    print("runnable")
  of procRunning:
    print("running ")
  of procSleeping:
    print("sleeping")
  of procZombie:
    print("zombie  ")


## Puts the current process to sleep for current for input.
proc sleepCurrentForInput*() =
  sleepCurrentFor(waitInput, 1)


## Puts the current process to sleep for current for ipc.
proc sleepCurrentForIpc*() =
  sleepCurrentFor(waitIpc, 1)


## Puts the current process to sleep for current for fs req.
proc sleepCurrentForFsReq*(reqId: U64) =
  sleepCurrentFor(waitFsReq, reqId)


## Puts the current process to sleep for current for block req.
proc sleepCurrentForBlockReq*(reqId: U64) =
  sleepCurrentFor(waitBlockReq, reqId)


## Puts the current process to sleep for current for pid.
proc sleepCurrentForPid*(pid: int32) =
  sleepCurrentFor(waitPid, U64(pid))


## Puts the current process to sleep for current until tick.
proc sleepCurrentUntilTick*(tick: U64) =
  sleepCurrentFor(waitTimer, tick)


## Puts the current process to sleep for current for pipe read.
proc sleepCurrentForPipeRead*(pipeId: I32) =
  sleepCurrentFor(waitPipeRead, U64(pipeId))


## Puts the current process to sleep for current for pipe write.
proc sleepCurrentForPipeWrite*(pipeId: I32) =
  sleepCurrentFor(waitPipeWrite, U64(pipeId))


## Puts the current process to sleep for current for poll.
proc sleepCurrentForPoll*(deadlineTick: U64) =
  sleepCurrentFor(waitPoll, deadlineTick)


## Wakes processes waiting for poll waiters.
proc wakePollWaiters*() =
  var mask = waitKindMasks[waitPoll]
  while mask != U64(0):
    let idx = lowestSetWaitIndex(mask)
    let bit = processSlotBit(idx)
    mask = mask and not bit

    if idx >= 0 and procs[idx].state == procSleeping and procs[idx].wait.kind == waitPoll:
      clearWait(addr procs[idx])
      procs[idx].state = procRunnable


## Wakes processes waiting for input waiters.
proc wakeInputWaiters*() =
  wakeWaiters(waitInput, 1, true)
  wakePollWaiters()


## Wakes processes waiting for ipc waiter.
proc wakeIpcWaiter*(pid: int32) =
  var mask = waitKindMasks[waitIpc]
  while mask != U64(0):
    let idx = lowestSetWaitIndex(mask)
    let bit = processSlotBit(idx)
    mask = mask and not bit

    if idx >= 0 and procs[idx].state == procSleeping and procs[idx].pid == pid and
        procs[idx].wait.kind == waitIpc:
      clearWait(addr procs[idx])
      procs[idx].state = procRunnable
      wakePollWaiters()
      return

  wakePollWaiters()


## Wakes processes waiting for fs waiter.
proc wakeFsWaiter*(reqId: U64) =
  wakeWaiters(waitFsReq, reqId, false)


## Wakes processes waiting for block waiter.
proc wakeBlockWaiter*(reqId: U64) =
  wakeWaiters(waitBlockReq, reqId, false)


## Wakes processes waiting for pid waiters.
proc wakePidWaiters*(pid: int32) =
  wakeWaiters(waitPid, U64(pid), true)
  wakePollWaiters()


## Wakes processes waiting for timer waiters.
proc wakeTimerWaiters*(tick: U64) =
  # Fast path:
  # Most ticks do not have an expired sleep/poll deadline.
  # Avoid scanning the whole process slot until earliest known deadline is reached.
  if timerDeadlineMask() == U64(0):
    return
  if tick < nextTimerWakeTick:
    return
  # Slow path:
  # At least one timer/poll deadline may have expired.
  # Scan only timer/poll waiters, wake expired sleepers,
  # then rebuild the cached earliest deadline.
  var mask = timerDeadlineMask()
  while mask != U64(0):
    let idx = lowestSetWaitIndex(mask)
    let bit = processSlotBit(idx)
    mask = mask and not bit

    if idx >= 0 and procs[idx].state == procSleeping and
        isTimerDeadlineWait(procs[idx].wait.kind) and
        procs[idx].wait.value <= tick:
      wakeTimerDeadlineProcess(addr procs[idx])

  recomputeTimerDeadlineWaiters()


## Wakes processes waiting for pipe readers.
proc wakePipeReaders*(pipeId: I32) =
  wakeWaiters(waitPipeRead, U64(pipeId), true)
  wakePollWaiters()


## Wakes processes waiting for pipe writers.
proc wakePipeWriters*(pipeId: I32) =
  wakeWaiters(waitPipeWrite, U64(pipeId), true)
  wakePollWaiters()


## Wakes processes waiting for process for signal.
proc wakeProcessForSignal(p: ptr Process) =
  if p == nil:
    return

  if p.state == procSleeping:
    clearWait(p)
    p.state = procRunnable

  wakePollWaiters()
  requestResched()


## Sends process signal.
proc sendProcessSignal*(pid: I32, signal: U32): int =
  let bit = signalBit(signal)
  if bit == U32(0):
    return -1

  let p = findProcessByPid(pid)
  if p == nil or p.state == procUnused or p.state == procZombie:
    return -1

  p.pendingSignals = p.pendingSignals or bit
  wakeProcessForSignal(p)
  0


## Implements the take process signal kernel helper.
proc takeProcessSignal*(p: ptr Process): U32 =
  if p == nil or p.pendingSignals == U32(0):
    return SysSignalNone

  let order = [
    SysSignalTerminate,
    SysSignalInterrupt,
    SysSignalChildExited,
    SysSignalServiceStopped,
  ]
  var i = 0
  while i < order.len:
    let signal = order[i]
    let bit = signalBit(signal)
    if (p.pendingSignals and bit) != U32(0):
      p.pendingSignals = p.pendingSignals and not bit
      return signal
    inc i

  SysSignalNone


## Implements the reap detached zombies kernel helper.
proc reapDetachedZombies() =
  var i = 0
  while i < MaxProcs:
    let p = addr procs[i]
    if p != currentProc and p.state == procZombie and p.detached:
      discardProcess(p)
    inc i


## Returns whether live parane is present.
proc hasLiveParane*(p: ptr Process): bool =
  if p == nil or p.parentPid <= 0:
    return false

  let parent = findProcessByPid(p.parentPid)
  parent != nil and parent.state != procUnused and parent.state != procZombie


## Implements the detach children of kernel helper.
proc detachChildrenOf*(parentPid: I32) =
  if parentPid <= 0:
    return

  var i = 0
  while i < MaxProcs:
    let child = addr procs[i]
    if child.state != procUnused and child.parentPid == parentPid:
      child.parentPid = 0
      child.detached = true
    inc i


## Marks process zombie.
proc markProcessZombie*(p: ptr Process, status: U64) =
  if p == nil:
    return

  let pid = p.pid
  let parentPid = p.parentPid

  detachChildrenOf(pid)

  p.exitStatus = status
  clearWait(p)
  clearFileState(p)
  p.pendingSignals = U32(0)
  p.state = procZombie

  if not p.detached and not hasLiveParane(p):
    p.detached = true
  wakePidWaiters(p.pid)

  if parentPid > 0:
    discard sendProcessSignal(parentPid, SysSignalChildExited)


## Implements the deliver current signals kernel helper.
proc deliverCurrentSignals*() =
  if currentProc == nil or not currentProc.user.active or currentProc.state == procZombie:
    return

  if (currentProc.pendingSignals and signalBit(SysSignalTerminate)) != U32(0):
    currentProc.pendingSignals =
      currentProc.pendingSignals and not signalBit(SysSignalTerminate)
    markProcessZombie(currentProc, U64(143))
    schedule()
    return

  if (currentProc.pendingSignals and signalBit(SysSignalInterrupt)) != U32(0):
    currentProc.pendingSignals =
      currentProc.pendingSignals and not signalBit(SysSignalInterrupt)
    markProcessZombie(currentProc, U64(130))
    schedule()


## Yields when the current process has a pending reschedule request.
proc maybeYieldOnResched*() =
  if not needResched:
    return

  needResched = false
  yieldCpu()


## Implements the kill current user process kernel helper.
proc killCurrentUserProcess*(status: U64) =
  if currentProc != nil and currentProc.user.active:
    markProcessZombie(currentProc, status)
    schedule()
