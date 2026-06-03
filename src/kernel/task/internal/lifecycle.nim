## Creates, configures, inherits, and tears down processes and user mappings.

## Clears user state.
proc clearUserState(p: ptr Process) =
  if p == nil:
    return

  p.user = UserState()


## Returns the process table slot index for a process pointer.
proc processSlotIndex(p: ptr Process): int =
  if p == nil:
    return -1

  let base = cast[U64](addr procs[0])
  let current = cast[U64](p)
  if current < base:
    return -1

  let offset = current - base
  if offset mod U64(sizeof(Process)) != U64(0):
    return -1

  let idx = int(offset div U64(sizeof(Process)))
  if idx < 0 or idx >= MaxProcs:
    return -1

  idx


## Returns the wait mask bit for a process table slot.
proc processSlotBit(idx: int): U64 =
  if idx < 0 or idx >= MaxProcs:
    return U64(0)

  U64(1) shl idx


## Returns the index of the lowest set bit in a wait mask.
proc lowestSetWaitIndex(mask: U64): int =
  if mask == U64(0):
    return -1

  var shifted = mask
  var idx = 0
  while (shifted and U64(1)) == U64(0):
    shifted = shifted shr 1
    inc idx

  idx


## Returns the mapped heap page count for a user state.
proc heapPageCount*(user: UserState): U64 =
  if user.heapEnd <= user.heapStart:
    return U64(0)

  alignUp(user.heapEnd - user.heapStart, PageSize) div PageSize


## Returns true when a wait kind is driven by timer deadlines.
proc isTimerDeadlineWait(kind: WaitKind): bool =
  kind == waitTimer or kind == waitPoll


## Returns the bitmask of timer-deadline based waiters.
proc timerDeadlineMask(): U64 =
  waitKindMasks[waitTimer] or waitKindMasks[waitPoll]


## Recomputes cached timer/poll waiter state from deadline wait masks.
proc recomputeTimerDeadlineWaiters() =
  nextTimerWakeTick = U64(0)

  var mask = timerDeadlineMask()
  while mask != U64(0):
    let idx = lowestSetWaitIndex(mask)
    let bit = processSlotBit(idx)
    mask = mask and not bit

    if idx >= 0:
      let p = addr procs[idx]
      if p.state == procSleeping and isTimerDeadlineWait(p.wait.kind):
        let deadline = p.wait.value
        if nextTimerWakeTick == U64(0) or deadline < nextTimerWakeTick:
          nextTimerWakeTick = deadline


## Registers a process in the wait-kind cache.
proc registerWaiter(p: ptr Process) =
  let idx = processSlotIndex(p)
  if idx < 0 or p.wait.kind == waitNone:
    return

  let bit = processSlotBit(idx)
  waitKindMasks[p.wait.kind] = waitKindMasks[p.wait.kind] or bit

  if isTimerDeadlineWait(p.wait.kind):
    if nextTimerWakeTick == U64(0) or p.wait.value < nextTimerWakeTick:
      nextTimerWakeTick = p.wait.value


## Unregisters a process from the wait-kind cache.
proc unregisterWaiter(p: ptr Process, updateTimerDeadline: bool) =
  let idx = processSlotIndex(p)
  if idx < 0 or p.wait.kind == waitNone:
    return

  let kind = p.wait.kind
  waitKindMasks[kind] = waitKindMasks[kind] and not processSlotBit(idx)

  if updateTimerDeadline and isTimerDeadlineWait(kind) and p.wait.value <= nextTimerWakeTick:
    recomputeTimerDeadlineWaiters()


## Clears wait state without forcing a timer deadline recompute.
proc clearWaitNoTimerRecompute(p: ptr Process) =
  if p == nil:
    return

  unregisterWaiter(p, false)
  p.wait = WaitTarget()


## Clears wait.
proc clearWait*(p: ptr Process) =
  if p == nil:
    return

  unregisterWaiter(p, true)
  p.wait = WaitTarget()


## Puts the current process to sleep for current for.
proc sleepCurrentFor(kind: WaitKind, value: U64) =
  if currentProc == nil:
    return

  currentProc.wait.kind = kind
  currentProc.wait.value = value
  currentProc.state = procSleeping
  registerWaiter(currentProc)
  schedule()
  deliverCurrentSignals()


## Wakes processes waiting for waiters.
proc wakeWaiters(kind: WaitKind, value: U64, wakeAll: bool) =
  var mask = waitKindMasks[kind]
  while mask != U64(0):
    let idx = lowestSetWaitIndex(mask)
    let bit = processSlotBit(idx)
    mask = mask and not bit

    if idx >= 0 and procs[idx].state == procSleeping and procs[idx].wait.kind == kind and
        procs[idx].wait.value == value:
      clearWait(addr procs[idx])
      procs[idx].state = procRunnable
      if not wakeAll:
        return


## Finds unused proc.
proc findUnusedProc(): ptr Process =
  var i = 0
  while i < MaxProcs:
    if procs[i].state == procUnused:
      return addr procs[i]
    inc i
  nil


## Returns whether free process slot is present.
proc hasFreeProcessSlot*(): bool =
  findUnusedProc() != nil


## Implements the current is idle process kernel helper.
proc currentIsIdleProcess*(): bool =
  currentProc != nil and currentProc == idleProc


## Implements the count current process cpu tick kernel helper.
proc countCurrentProcessCpuTick*() =
  if currentProc != nil:
    saturatingIncU64(currentProc.cpuTicks)
    saturatingIncU64(currentProc.cpuWindowTicks)


## Implements the snapshot process cpu window kernel helper.
proc snapshotProcessCpuWindow*(windowTicks: U64) =
  var i = 0
  while i < MaxProcs:
    if procs[i].state != procUnused:
      procs[i].cpuPercent =
        if windowTicks == U64(0):
          U32(0)
        else:
          U32((procs[i].cpuWindowTicks * U64(100)) div windowTicks)
      procs[i].cpuWindowTicks = U64(0)
    inc i


## Implements the idle task kernel helper.
proc idleTask() {.cdecl.} =
  while true:
    maybeYieldOnResched()
    arch.writeSstatus(arch.readSstatus() or SstatusSie)
    arch.wfi()


## Implements the assign pid kernel helper.
proc assignPid(): I32 =
  var i = 0
  while i < MaxProcs:
    if procs[i].state == procUnused:
      inc i
      continue
    if procs[i].pid == nextPid:
      inc nextPid
      i = 0
      continue
    inc i
  nextPid


## Creates kernel process internal.
proc createKernelProcessInternal(
  entry: KernelTask,
  isIdle: bool,
  name: cstring,
  initialState: ProcessState = procRunnable,
): int32 =
  let p = findUnusedProc()
  if p == nil or entry == nil:
    return -1

  let stack = palloc(KernelStackPages)
  if stack == NilPAddr:
    return -1

  p.pid = assignPid()
  inc nextPid
  p.parentPid = 0
  setIdentity(p, RootUid, RootGid)
  setExePath(p, name)
  p.state = initialState
  p.entry = entry
  p.kernelStack = stack
  p.rootPageTable = nil
  setRootCwd(p)
  clearUserState(p)
  clearWait(p)
  p.detached = false
  p.exitStatus = 0
  p.pendingSignals = U32(0)
  p.lastError = SysErrOk
  clearIpcQueue(p)
  initStandardFiles(p)
  p.context = Context()
  p.context.sp = stack + KernelStackPages * PageSize
  p.context.ra = cast[U64](processBootstrap)

  if isIdle:
    idleProc = p

  p.pid


## Implements the process init kernel helper.
proc processInit*() =
  var i = 0
  while i < MaxProcs:
    procs[i].pid = 0
    procs[i].parentPid = 0
    setIdentity(addr procs[i], RootUid, RootGid)
    setExePath(addr procs[i], "init")
    setRootCwd(addr procs[i])
    procs[i].state = procUnused
    procs[i].context = Context()
    procs[i].entry = nil
    procs[i].kernelStack = NilPAddr
    procs[i].rootPageTable = nil
    clearUserState(addr procs[i])
    clearWait(addr procs[i])
    procs[i].detached = false
    procs[i].exitStatus = 0
    procs[i].pendingSignals = U32(0)
    procs[i].lastError = SysErrOk
    clearIpcQueue(addr procs[i])
    clearFileState(addr procs[i])
    inc i

  currentProc = nil
  nextPid = 1
  needResched = false
  idleProc = nil
  kernelPageTable = nil
  var waitKindIndex = int(low(WaitKind))
  while waitKindIndex <= int(high(WaitKind)):
    waitKindMasks[WaitKind(waitKindIndex)] = U64(0)
    inc waitKindIndex
  nextTimerWakeTick = U64(0)

  var pipeIdx = U32(0)
  while pipeIdx < SysPipeMax:
    pipes[pipeIdx] = PipeState()
    inc pipeIdx

  if createKernelProcessInternal(idleTask, true, "init") < 0:
    panic("failed to create idle task")


## Creates kernel process named.
proc createKernelProcessNamed*(entry: KernelTask, name: cstring): int32 =
  createKernelProcessInternal(entry, false, name)


## Creates kernel process.
proc createKernelProcess*(entry: KernelTask): int32 =
  createKernelProcessNamed(entry, "kernel_task")


## Implements the user process bootstrap kernel helper.
proc userProcessBootstrap() {.cdecl, noreturn.} =
  if currentProc == nil or not currentProc.user.active:
    panic("invalid user process")

  let kernelSp = currentProc.kernelStack + KernelStackPages * PageSize
  arch.enterUser(currentProc.user.pc, currentProc.user.sp, kernelSp, currentProc.user.arg0, currentProc.user.arg1)


## Finds process by pid.
proc findProcessByPid*(pid: int32): ptr Process =
  var i = 0
  while i < MaxProcs:
    if procs[i].state != procUnused and procs[i].pid == pid:
      return addr procs[i]
    inc i
  nil


## Implements the inherit process metadata kernel helper.
proc inheritProcessMetadata*(child, parent: ptr Process) =
  clearFileState(child)

  if parent == nil:
    child.parentPid = 0
    setIdentity(child, RootUid, RootGid)
    setRootCwd(child)
    initStandardFiles(child)
    return

  child.parentPid = parent.pid
  child.identity = parent.identity
  copyCwd(child.cwd, parent.cwd)
  copyFileState(child, parent)
  # Future per-process attributes such as rootfs should be copied here.


## Allocates user process from parent.
proc allocUserProcessFromParent*(parent: ptr Process, inheritMetadata: bool = true): ptr Process =
  let pid = createKernelProcessInternal(userProcessBootstrap, false, "user_proc", procSleeping)
  if pid < 0:
    return nil

  let p = findProcessByPid(pid)
  if p == nil:
    return nil

  p.user.active = true
  if inheritMetadata:
    inheritProcessMetadata(p, parent)
  p


## Configures user process.
proc configureUserProcess*(p: ptr Process, root: PageTable, path: cstring,
                           userBase, userPc, userStackTop, userSp: VAddr,
                           imagePages, stackPages: U64, arg0: U64 = 0,
                           arg1: U64 = 0, requestedCapabilityMask: U32 = U32(0),
                           capabilityMask: U32 = U32(0)) =
  setExePath(p, path)
  p.rootPageTable = root
  p.user.active = true
  p.user.base = userBase
  p.user.pc = userPc
  p.user.stackTop = userStackTop
  p.user.sp = userSp
  p.user.imagePages = imagePages
  p.user.stackPages = stackPages

  p.user.heapStart = userBase + imagePages * PageSize
  p.user.heapEnd = p.user.heapStart

  const
    UserHeapStackGuardPages = U64(1)

  let stackBottom = userStackTop - stackPages * PageSize
  let guardSize = UserHeapStackGuardPages * PageSize

  p.user.heapLimit =
    if stackBottom <= p.user.heapStart + guardSize:
      p.user.heapStart
    else:
      stackBottom - guardSize
  if p.user.heapStart > p.user.heapLimit:
    panic("user heap overlaps stack")

  p.user.requestedCapabilityMask = requestedCapabilityMask
  p.user.capabilityMask = capabilityMask
  p.user.arg0 = arg0
  p.user.arg1 = arg1
  p.pendingSignals = U32(0)
  clearWait(p)
  p.exitStatus = 0
  p.state = procRunnable


## Sets user rkx map.
proc setUserRkxMap*(p: ptr Process, textVa, textMemSize, rodataVa, rodataMemSize,
                    dataVa, dataMemSize, bssVa, bssMemSize: U64) =
  if p == nil:
    return

  p.user.textVa = textVa
  p.user.textMemSize = textMemSize
  p.user.rodataVa = rodataVa
  p.user.rodataMemSize = rodataMemSize
  p.user.dataVa = dataVa
  p.user.dataMemSize = dataMemSize
  p.user.bssVa = bssVa
  p.user.bssMemSize = bssMemSize


## Releases user address space.
proc releaseUserAddressSpace(p: ptr Process) =
  if p.rootPageTable == nil or p.rootPageTable == kernelPageTable:
    return

  let oldSatp = arch.readSatp()
  let kernelSatp =
    if kernelPageTable == nil:
      U64(0)
    else:
      makeSatp(cast[PAddr](kernelPageTable))
  let restoreSatp = currentProc != p and kernelSatp != U64(0) and oldSatp != kernelSatp

  if restoreSatp:
    arch.writeSatp(kernelSatp)
    arch.flushTlb()

  discard unmapRangeFree(p.rootPageTable, p.user.base, p.user.imagePages)
  if p.user.stackTop != 0 and p.user.stackPages != 0:
    discard unmapRangeFree(
      p.rootPageTable,
      p.user.stackTop - p.user.stackPages * PageSize,
      p.user.stackPages,
    )
  let heapPages = heapPageCount(p.user)
  if heapPages != 0:
    discard unmapRangeFree(p.rootPageTable, p.user.heapStart, heapPages)

  freePageTablePages(p.rootPageTable)
  p.rootPageTable = nil

  if restoreSatp:
    arch.writeSatp(oldSatp)
    arch.flushTlb()


## Implements the discard process kernel helper.
proc discardProcess*(p: ptr Process) =
  if p == nil:
    return

  releaseUserAddressSpace(p)

  if p.kernelStack != NilPAddr:
    discard pfree(p.kernelStack, KernelStackPages)

  p.pid = 0
  p.parentPid = 0
  setIdentity(p, RootUid, RootGid)
  setExePath(p, "init_proc")
  setRootCwd(p)
  p.state = procUnused
  p.context = Context()
  p.entry = nil
  p.kernelStack = NilPAddr
  p.rootPageTable = nil
  clearUserState(p)
  clearWait(p)
  p.detached = false
  p.exitStatus = 0
  p.pendingSignals = U32(0)
  p.lastError = SysErrOk
  p.cpuTicks = 0
  p.cpuWindowTicks = 0
  p.cpuPercent = 0
  clearIpcQueue(p)
  clearFileState(p)


## Creates user process.
proc createUserProcess*(path: cstring, userBase, userPc, userStackTop, userSp: VAddr,
                        imagePages, stackPages: U64, arg0: U64 = 0, arg1: U64 = 0): int32 =
  let p = allocUserProcessFromParent(nil)
  if p == nil:
    return -1

  configureUserProcess(p, kernelPageTable, path, userBase, userPc, userStackTop, userSp,
                       imagePages, stackPages, arg0, arg1)
  p.pid


## Returns whether runnable process is present.
proc hasRunnableProcess*(): bool =
  var i = 0
  while i < MaxProcs:
    if procs[i].state == procRunnable:
      return true
    inc i
  false
