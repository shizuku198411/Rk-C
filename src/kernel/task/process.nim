import ../../arch/riscv64/arch
import ../../lib/calc
import ../../lib/fixed_string
import ../../lib/syscall_types
import ../../lib/types
import ../dev/console
import ../mm/memory
import ../mm/paging

const
  MaxProcs* = int(SysProcessMaxSlots)
  KernelStackPages* = U64(4)

type
  ProcessState* = enum
    procUnused = 0
    procRunnable
    procRunning
    procSleeping
    procZombie

  WaitKind* = enum
    waitNone = 0
    waitInput
    waitIpc
    waitPid
    waitFsReq
    waitBlockReq
    waitTimer
    waitPipeRead
    waitPipeWrite
    waitPoll

  WaitTarget* {.bycopy.} = object
    kind*: WaitKind
    value*: U64

  IpcState* {.bycopy.} = object
    queue*: array[SysIpcQueueCap, SysIpcPacket]
    head*: int
    tail*: int
    count*: int

  UserState* {.bycopy.} = object
    active*: bool
    base*: VAddr
    pc*: VAddr
    stackTop*: VAddr
    sp*: VAddr
    imagePages*: U64
    stackPages*: U64
    textVa*: VAddr
    textMemSize*: U64
    rodataVa*: VAddr
    rodataMemSize*: U64
    dataVa*: VAddr
    dataMemSize*: U64
    bssVa*: VAddr
    bssMemSize*: U64
    requestedCapabilityMask*: U32
    capabilityMask*: U32
    arg0*: U64
    arg1*: U64

  FdEntry* {.bycopy.} = object
    used*: bool
    kind*: U32
    flags*: U32
    offset*: U64
    size*: U64
    pipeId*: I32
    path*: array[SysFdPathMax, char]

  FileState* {.bycopy.} = object
    entries*: array[SysFdMax, FdEntry]

  PipeState* {.bycopy.} = object
    used*: bool
    readers*: U32
    writers*: U32
    head*: U32
    tail*: U32
    count*: U32
    data*: array[SysPipeBufSize, U8]

  Context* {.bycopy.} = object
    ra*: U64
    sp*: U64
    s0*: U64
    s1*: U64
    s2*: U64
    s3*: U64
    s4*: U64
    s5*: U64
    s6*: U64
    s7*: U64
    s8*: U64
    s9*: U64
    s10*: U64
    s11*: U64

  KernelTask* = proc() {.cdecl.}

  Process* {.bycopy.} = object
    pid*: int32
    parentPid*: int32
    exePath*: cstring
    exePathBuf*: array[SysProcessNameMax, char]
    cwd*: array[SysProcessCwdMax, char]
    state*: ProcessState
    context*: Context
    entry*: KernelTask
    kernelStack*: PAddr
    rootPageTable*: PageTable
    user*: UserState
    wait*: WaitTarget
    detached*: bool
    exitStatus*: U64
    cpuTicks*: U64
    cpuWindowTicks*: U64
    cpuPercent*: U32
    ipc*: IpcState
    files*: FileState


var
  procs*: array[MaxProcs, Process]
  currentProc*: ptr Process
  nextPid = int32(1)
  needResched {.volatile.}: bool
  idleProc: ptr Process
  kernelPageTable: PageTable
  pipes: array[SysPipeMax, PipeState]


proc contextSwitch(prev: ptr Context, next: ptr Context) {.importc: "context_switch", cdecl.}
proc processBootstrap*() {.exportc: "process_bootstrap", cdecl.}
proc schedule*()
proc yieldCpu*()
proc maybeYieldOnResched*()
proc printProcessState*(state: ProcessState)
proc createKernelProcessNamed*(entry: KernelTask, name: cstring): int32
proc sleepCurrentForInput*()
proc sleepCurrentForIpc*()
proc sleepCurrentForFsReq*(reqId: U64)
proc sleepCurrentForBlockReq*(reqId: U64)
proc sleepCurrentForPid*(pid: int32)
proc sleepCurrentUntilTick*(tick: U64)
proc sleepCurrentForPipeRead*(pipeId: I32)
proc sleepCurrentForPipeWrite*(pipeId: I32)
proc sleepCurrentForPoll*(deadlineTick: U64)
proc wakeInputWaiters*()
proc wakeIpcWaiter*(pid: int32)
proc wakeFsWaiter*(reqId: U64)
proc wakeBlockWaiter*(reqId: U64)
proc wakePidWaiters*(pid: int32)
proc wakeTimerWaiters*(tick: U64)
proc wakePipeReaders*(pipeId: I32)
proc wakePipeWriters*(pipeId: I32)
proc wakePollWaiters*()
proc clearWait*(p: ptr Process)


proc setKernelPageTable*(root: PageTable) =
  kernelPageTable = root


proc setRootCwd(p: ptr Process) =
  p.cwd[0] = '/'
  p.cwd[1] = '\0'


proc setExePath(p: ptr Process, path: cstring) =
  discard copyCString(p.exePathBuf, path)
  p.exePath = cast[cstring](addr p.exePathBuf[0])


proc copyCwd(dst: var array[SysProcessCwdMax, char], src: array[SysProcessCwdMax, char]) =
  copyChars(dst, src)


proc clearIpcQueue(p: ptr Process) =
  p.ipc.head = 0
  p.ipc.tail = 0
  p.ipc.count = 0

  var i = 0
  while i < SysIpcQueueCap:
    p.ipc.queue[i] = SysIpcPacket()
    inc i


proc pipeNext(index: U32): U32 =
  (index + 1) mod SysPipeBufSize


proc validPipeId(pipeId: I32): bool =
  pipeId >= 0 and pipeId < I32(SysPipeMax) and pipes[U32(pipeId)].used


proc allocPipe*(): I32 =
  var i = U32(0)
  while i < SysPipeMax:
    if not pipes[i].used:
      pipes[i] = PipeState()
      pipes[i].used = true
      pipes[i].readers = 1
      pipes[i].writers = 1
      return I32(i)

    inc i

  -1


proc freePipe*(pipeId: I32) =
  if validPipeId(pipeId):
    pipes[U32(pipeId)] = PipeState()


proc retainFdEntry*(entry: FdEntry) =
  if entry.used and entry.kind == SysFdKindPipe and validPipeId(entry.pipeId):
    if (entry.flags and SysOpenRead) != 0:
      inc pipes[U32(entry.pipeId)].readers
    if (entry.flags and SysOpenWrite) != 0:
      inc pipes[U32(entry.pipeId)].writers


proc releaseFdEntry*(entry: FdEntry) =
  if not entry.used or entry.kind != SysFdKindPipe or not validPipeId(entry.pipeId):
    return

  let pipe = addr pipes[U32(entry.pipeId)]
  if (entry.flags and SysOpenRead) != 0 and pipe.readers > 0:
    dec pipe.readers
    wakePipeWriters(entry.pipeId)
  if (entry.flags and SysOpenWrite) != 0 and pipe.writers > 0:
    dec pipe.writers
    wakePipeReaders(entry.pipeId)

  if pipe.readers == 0 and pipe.writers == 0:
    pipe[] = PipeState()


proc pipeReadKernel*(pipeId: I32, dst: ptr UncheckedArray[U8], len: U64): I32 =
  if dst == nil or not validPipeId(pipeId):
    return -1

  let pipe = addr pipes[U32(pipeId)]
  var readLen = U64(0)
  while readLen < len:
    while pipe.count == 0:
      if pipe.writers == 0:
        return I32(readLen)
      sleepCurrentForPipeRead(pipeId)
      if not validPipeId(pipeId):
        return -1

    dst[readLen] = pipe.data[pipe.head]
    pipe.head = pipeNext(pipe.head)
    dec pipe.count
    inc readLen
    wakePipeWriters(pipeId)

  I32(readLen)


proc pipeWriteKernel*(pipeId: I32, src: ptr UncheckedArray[U8], len: U64): I32 =
  if src == nil or not validPipeId(pipeId):
    return -1

  let pipe = addr pipes[U32(pipeId)]
  var written = U64(0)
  while written < len:
    if pipe.readers == 0:
      return -1

    while pipe.count == SysPipeBufSize:
      if pipe.readers == 0:
        return -1
      sleepCurrentForPipeWrite(pipeId)
      if not validPipeId(pipeId):
        return -1

    pipe.data[pipe.tail] = src[written]
    pipe.tail = pipeNext(pipe.tail)
    inc pipe.count
    inc written
    wakePipeReaders(pipeId)

  I32(written)


proc pipeReadable*(pipeId: I32): bool =
  if not validPipeId(pipeId):
    return false

  let pipe = addr pipes[U32(pipeId)]
  pipe.count > 0 or pipe.writers == 0


proc pipeWritable*(pipeId: I32): bool =
  if not validPipeId(pipeId):
    return false

  let pipe = addr pipes[U32(pipeId)]
  pipe.readers > 0 and pipe.count < SysPipeBufSize


proc clearFileState*(p: ptr Process) =
  var i = U32(0)
  while i < SysFdMax:
    releaseFdEntry(p.files.entries[i])
    inc i

  p.files = FileState()


proc setFdPath(entry: var FdEntry, path: cstring) =
  var i = U32(0)
  while i < SysFdPathMax - 1 and path != nil and path[i] != '\0':
    entry.path[i] = path[i]
    inc i

  while i < SysFdPathMax:
    entry.path[i] = '\0'
    inc i


proc initStandardFiles*(p: ptr Process) =
  clearFileState(p)

  p.files.entries[0].used = true
  p.files.entries[0].kind = SysFdKindStdin
  p.files.entries[0].flags = SysOpenRead
  setFdPath(p.files.entries[0], "/dev/stdin")

  p.files.entries[1].used = true
  p.files.entries[1].kind = SysFdKindStdout
  p.files.entries[1].flags = SysOpenWrite
  setFdPath(p.files.entries[1], "/dev/stdout")

  p.files.entries[2].used = true
  p.files.entries[2].kind = SysFdKindStderr
  p.files.entries[2].flags = SysOpenWrite
  setFdPath(p.files.entries[2], "/dev/stderr")


proc copyFileState(dst, src: ptr Process) =
  dst.files = src.files
  var i = U32(0)
  while i < SysFdMax:
    retainFdEntry(dst.files.entries[i])
    inc i


proc clearUserState(p: ptr Process) =
  if p == nil:
    return

  p.user = UserState()


proc clearWait*(p: ptr Process) =
  if p == nil:
    return

  p.wait = WaitTarget()


proc sleepCurrentFor(kind: WaitKind, value: U64) =
  if currentProc == nil:
    return

  currentProc.wait.kind = kind
  currentProc.wait.value = value
  currentProc.state = procSleeping
  schedule()


proc wakeWaiters(kind: WaitKind, value: U64, wakeAll: bool) =
  var i = 0
  while i < MaxProcs:
    if procs[i].state == procSleeping and procs[i].wait.kind == kind and
        procs[i].wait.value == value:
      clearWait(addr procs[i])
      procs[i].state = procRunnable
      if not wakeAll:
        return
    inc i


proc findUnusedProc(): ptr Process =
  var i = 0
  while i < MaxProcs:
    if procs[i].state == procUnused:
      return addr procs[i]
    inc i
  nil


proc hasFreeProcessSlot*(): bool =
  findUnusedProc() != nil


proc currentIsIdleProcess*(): bool =
  currentProc != nil and currentProc == idleProc


proc countCurrentProcessCpuTick*() =
  if currentProc != nil:
    saturatingIncU64(currentProc.cpuTicks)
    saturatingIncU64(currentProc.cpuWindowTicks)


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


proc idleTask() {.cdecl.} =
  while true:
    maybeYieldOnResched()
    arch.writeSstatus(arch.readSstatus() or SstatusSie)
    arch.wfi()


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


proc createKernelProcessInternal(entry: KernelTask, isIdle: bool, name: cstring): int32 =
  let p = findUnusedProc()
  if p == nil or entry == nil:
    return -1

  let stack = palloc(KernelStackPages)
  if stack == NilPAddr:
    return -1

  p.pid = assignPid()
  inc nextPid
  p.parentPid = 0
  setExePath(p, name)
  p.state = procRunnable
  p.entry = entry
  p.kernelStack = stack
  p.rootPageTable = nil
  setRootCwd(p)
  clearUserState(p)
  clearWait(p)
  p.detached = false
  p.exitStatus = 0
  clearIpcQueue(p)
  initStandardFiles(p)
  p.context = Context()
  p.context.sp = stack + KernelStackPages * PageSize
  p.context.ra = cast[U64](processBootstrap)

  if isIdle:
    idleProc = p

  p.pid


proc processInit*() =
  var i = 0
  while i < MaxProcs:
    procs[i].pid = 0
    procs[i].parentPid = 0
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
    clearIpcQueue(addr procs[i])
    clearFileState(addr procs[i])
    inc i

  currentProc = nil
  nextPid = 1
  needResched = false
  idleProc = nil
  kernelPageTable = nil
  var pipeIdx = U32(0)
  while pipeIdx < SysPipeMax:
    pipes[pipeIdx] = PipeState()
    inc pipeIdx

  if createKernelProcessInternal(idleTask, true, "init") < 0:
    panic("failed to create idle task")


proc createKernelProcessNamed*(entry: KernelTask, name: cstring): int32 =
  createKernelProcessInternal(entry, false, name)


proc createKernelProcess*(entry: KernelTask): int32 =
  createKernelProcessNamed(entry, "kernel_task")


proc userProcessBootstrap() {.cdecl, noreturn.} =
  if currentProc == nil or not currentProc.user.active:
    panic("invalid user process")

  let kernelSp = currentProc.kernelStack + KernelStackPages * PageSize
  arch.enterUser(currentProc.user.pc, currentProc.user.sp, kernelSp, currentProc.user.arg0, currentProc.user.arg1)


proc findProcessByPid*(pid: int32): ptr Process =
  var i = 0
  while i < MaxProcs:
    if procs[i].state != procUnused and procs[i].pid == pid:
      return addr procs[i]
    inc i
  nil


proc inheritProcessMetadata*(child, parent: ptr Process) =
  clearFileState(child)

  if parent == nil:
    child.parentPid = 0
    setRootCwd(child)
    initStandardFiles(child)
    return

  child.parentPid = parent.pid
  copyCwd(child.cwd, parent.cwd)
  copyFileState(child, parent)
  # Future per-process attributes such as rootfs should be copied here.


proc allocUserProcessFromParent*(parent: ptr Process, inheritMetadata: bool = true): ptr Process =
  let pid = createKernelProcessInternal(userProcessBootstrap, false, "user_proc")
  if pid < 0:
    return nil

  let p = findProcessByPid(pid)
  if p == nil:
    return nil

  p.state = procSleeping
  p.user.active = true
  if inheritMetadata:
    inheritProcessMetadata(p, parent)
  p


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
  p.user.requestedCapabilityMask = requestedCapabilityMask
  p.user.capabilityMask = capabilityMask
  p.user.arg0 = arg0
  p.user.arg1 = arg1
  clearWait(p)
  p.exitStatus = 0
  p.state = procRunnable


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


proc releaseUserAddressSpace(p: ptr Process) =
  if p.rootPageTable == nil or p.rootPageTable == kernelPageTable:
    return

  discard unmapRangeFree(p.rootPageTable, p.user.base, p.user.imagePages)
  if p.user.stackTop != 0 and p.user.stackPages != 0:
    discard unmapRangeFree(
      p.rootPageTable,
      p.user.stackTop - p.user.stackPages * PageSize,
      p.user.stackPages,
    )

  freePageTablePages(p.rootPageTable)
  p.rootPageTable = nil


proc discardProcess*(p: ptr Process) =
  if p == nil:
    return

  releaseUserAddressSpace(p)

  if p.kernelStack != NilPAddr:
    discard pfree(p.kernelStack, KernelStackPages)

  p.pid = 0
  p.parentPid = 0
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
  p.cpuTicks = 0
  p.cpuWindowTicks = 0
  p.cpuPercent = 0
  clearIpcQueue(p)
  clearFileState(p)


proc createUserProcess*(path: cstring, userBase, userPc, userStackTop, userSp: VAddr,
                        imagePages, stackPages: U64, arg0: U64 = 0, arg1: U64 = 0): int32 =
  let p = allocUserProcessFromParent(nil)
  if p == nil:
    return -1

  configureUserProcess(p, kernelPageTable, path, userBase, userPc, userStackTop, userSp,
                       imagePages, stackPages, arg0, arg1)
  p.pid


proc hasRunnableProcess*(): bool =
  var i = 0
  while i < MaxProcs:
    if procs[i].state == procRunnable:
      return true
    inc i
  false


proc requestResched*() =
  needResched = true


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


proc sleepCurrentForInput*() =
  sleepCurrentFor(waitInput, 1)


proc sleepCurrentForIpc*() =
  sleepCurrentFor(waitIpc, 1)


proc sleepCurrentForFsReq*(reqId: U64) =
  sleepCurrentFor(waitFsReq, reqId)


proc sleepCurrentForBlockReq*(reqId: U64) =
  sleepCurrentFor(waitBlockReq, reqId)


proc sleepCurrentForPid*(pid: int32) =
  sleepCurrentFor(waitPid, U64(pid))


proc sleepCurrentUntilTick*(tick: U64) =
  sleepCurrentFor(waitTimer, tick)


proc sleepCurrentForPipeRead*(pipeId: I32) =
  sleepCurrentFor(waitPipeRead, U64(pipeId))


proc sleepCurrentForPipeWrite*(pipeId: I32) =
  sleepCurrentFor(waitPipeWrite, U64(pipeId))


proc sleepCurrentForPoll*(deadlineTick: U64) =
  sleepCurrentFor(waitPoll, deadlineTick)


proc wakePollWaiters*() =
  var i = 0
  while i < MaxProcs:
    if procs[i].state == procSleeping and procs[i].wait.kind == waitPoll:
      clearWait(addr procs[i])
      procs[i].state = procRunnable
    inc i


proc wakeInputWaiters*() =
  wakeWaiters(waitInput, 1, true)
  wakePollWaiters()


proc wakeIpcWaiter*(pid: int32) =
  var i = 0
  while i < MaxProcs:
    if procs[i].state == procSleeping and procs[i].pid == pid and procs[i].wait.kind == waitIpc:
      clearWait(addr procs[i])
      procs[i].state = procRunnable
      wakePollWaiters()
      return
    inc i

  wakePollWaiters()


proc wakeFsWaiter*(reqId: U64) =
  wakeWaiters(waitFsReq, reqId, false)


proc wakeBlockWaiter*(reqId: U64) =
  wakeWaiters(waitBlockReq, reqId, false)


proc wakePidWaiters*(pid: int32) =
  wakeWaiters(waitPid, U64(pid), true)
  wakePollWaiters()


proc wakeTimerWaiters*(tick: U64) =
  var i = 0
  while i < MaxProcs:
    if procs[i].state == procSleeping and
        (procs[i].wait.kind == waitTimer or procs[i].wait.kind == waitPoll) and
        procs[i].wait.value <= tick:
      clearWait(addr procs[i])
      procs[i].state = procRunnable
    inc i


proc wakePipeReaders*(pipeId: I32) =
  wakeWaiters(waitPipeRead, U64(pipeId), true)
  wakePollWaiters()


proc wakePipeWriters*(pipeId: I32) =
  wakeWaiters(waitPipeWrite, U64(pipeId), true)
  wakePollWaiters()


proc reapDetachedZombies() =
  var i = 0
  while i < MaxProcs:
    let p = addr procs[i]
    if p != currentProc and p.state == procZombie and p.detached:
      discardProcess(p)
    inc i


proc hasLiveParane*(p: ptr Process): bool =
  if p == nil or p.parentPid <= 0:
    return false

  let parent = findProcessByPid(p.parentPid)
  parent != nil and parent.state != procUnused and parent.state != procZombie


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


proc markProcessZombie*(p: ptr Process, status: U64) =
  if p == nil:
    return

  let pid = p.pid

  detachChildrenOf(pid)

  p.exitStatus = status
  clearWait(p)
  clearFileState(p)
  p.state = procZombie

  if not p.detached and not hasLiveParane(p):
    p.detached = true
  wakePidWaiters(p.pid)


proc maybeYieldOnResched*() =
  if not needResched:
    return

  needResched = false
  yieldCpu()


proc killCurrentUserProcess*(status: U64) =
  if currentProc != nil and currentProc.user.active:
    markProcessZombie(currentProc, status)
    schedule()


proc processBootstrap*() =
  if currentProc == nil or currentProc.entry == nil:
    panic("invalid current process")

  currentProc.entry()
  currentProc.state = procZombie
  schedule()
  panic("zombie process resumed")


proc schedule*() =
  let prev = currentProc
  var start = 0
  var next: ptr Process = nil

  reapDetachedZombies()

  if currentProc != nil:
    let currentIndex = (cast[U64](currentProc) - cast[U64](addr procs[0])) div U64(sizeof(Process))
    start = int((currentIndex + 1'u64) mod U64(MaxProcs))

  var i = 0
  while i < MaxProcs:
    let idx = (start + i) mod MaxProcs
    let candidate = addr procs[idx]

    if candidate != idleProc and candidate.state == procRunnable:
      next = candidate
      break

    inc i

  if next == nil and idleProc != nil and
      (idleProc.state == procRunnable or idleProc.state == procRunning):
    next = idleProc

  if next == nil:
    if prev != nil and (prev.state == procRunning or prev.state == procRunnable):
      prev.state = procRunning
      currentProc = prev
      return

    panic("no runnable process")

  next.state = procRunning
  currentProc = next
  let nextRoot =
    if next.rootPageTable != nil:
      next.rootPageTable
    else:
      kernelPageTable

  if nextRoot != nil:
    arch.writeSatp(makeSatp(cast[PAddr](nextRoot)))
    paging.flushTlb()

  arch.writeSscratch(next.kernelStack + KernelStackPages * PageSize)

  if prev == next:
    return

  if prev == nil:
    var dummy = Context()
    contextSwitch(addr dummy, addr next.context)
  else:
    contextSwitch(addr prev.context, addr next.context)


proc yieldCpu*() =
  if currentProc == nil and not hasRunnableProcess():
    return

  if currentProc != nil and currentProc.state == procRunning:
    currentProc.state = procRunnable

  schedule()
