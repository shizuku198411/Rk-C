## Implements process state, scheduling, waits, fd state, pipes, and signals.
import ../../arch/riscv64/arch
import ../../lib/calc
import ../../lib/fixed_string
import ../../lib/syscall_types
import ../../lib/types
import ../../lib/user_ids
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
    heapStart*: VAddr
    heapEnd*: VAddr
    heapLimit*: VAddr
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

  ProcessIdentity* {.bycopy.} = object
    uid*: U32
    gid*: U32

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
    identity*: ProcessIdentity
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
    pendingSignals*: U32
    lastError*: I32
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


## Imports the assembly context switch routine.
proc contextSwitch(prev: ptr Context, next: ptr Context) {.importc: "context_switch", cdecl.}
## Runs the initial trampoline for a newly scheduled process.
proc processBootstrap*() {.exportc: "process_bootstrap", cdecl.}
## Selects the next runnable process and switches to it.
proc schedule*()
## Yields the current process to the scheduler.
proc yieldCpu*()
## Yields when the current process has a pending reschedule request.
proc maybeYieldOnResched*()
## Prints process state.
proc printProcessState*(state: ProcessState)
## Creates kernel process named.
proc createKernelProcessNamed*(entry: KernelTask, name: cstring): int32
## Puts the current process to sleep for current for input.
proc sleepCurrentForInput*()
## Puts the current process to sleep for current for ipc.
proc sleepCurrentForIpc*()
## Puts the current process to sleep for current for fs req.
proc sleepCurrentForFsReq*(reqId: U64)
## Puts the current process to sleep for current for block req.
proc sleepCurrentForBlockReq*(reqId: U64)
## Puts the current process to sleep for current for pid.
proc sleepCurrentForPid*(pid: int32)
## Puts the current process to sleep for current until tick.
proc sleepCurrentUntilTick*(tick: U64)
## Puts the current process to sleep for current for pipe read.
proc sleepCurrentForPipeRead*(pipeId: I32)
## Puts the current process to sleep for current for pipe write.
proc sleepCurrentForPipeWrite*(pipeId: I32)
## Puts the current process to sleep for current for poll.
proc sleepCurrentForPoll*(deadlineTick: U64)
## Wakes processes waiting for input waiters.
proc wakeInputWaiters*()
## Wakes processes waiting for ipc waiter.
proc wakeIpcWaiter*(pid: int32)
## Wakes processes waiting for fs waiter.
proc wakeFsWaiter*(reqId: U64)
## Wakes processes waiting for block waiter.
proc wakeBlockWaiter*(reqId: U64)
## Wakes processes waiting for pid waiters.
proc wakePidWaiters*(pid: int32)
## Wakes processes waiting for timer waiters.
proc wakeTimerWaiters*(tick: U64)
## Wakes processes waiting for pipe readers.
proc wakePipeReaders*(pipeId: I32)
## Wakes processes waiting for pipe writers.
proc wakePipeWriters*(pipeId: I32)
## Wakes processes waiting for poll waiters.
proc wakePollWaiters*()
## Clears wait.
proc clearWait*(p: ptr Process)
## Marks process zombie.
proc markProcessZombie*(p: ptr Process, status: U64)
## Sends process signal.
proc sendProcessSignal*(pid: I32, signal: U32): int
## Implements the take process signal kernel helper.
proc takeProcessSignal*(p: ptr Process): U32
## Implements the deliver current signals kernel helper.
proc deliverCurrentSignals*()


## Sets kernel page table.
proc setKernelPageTable*(root: PageTable) =
  kernelPageTable = root


## Sets root cwd.
proc setRootCwd(p: ptr Process) =
  p.cwd[0] = '/'
  p.cwd[1] = '\0'


## Sets identity.
proc setIdentity(p: ptr Process, uid, gid: U32) =
  p.identity.uid = uid
  p.identity.gid = gid


## Sets last error.
proc setLastError*(err: I32) =
  if currentProc != nil:
    currentProc.lastError = err


## Clears last error.
proc clearLastError*() =
  setLastError(SysErrOk)


## Sets exe path.
proc setExePath(p: ptr Process, path: cstring) =
  discard copyCString(p.exePathBuf, path)
  p.exePath = cast[cstring](addr p.exePathBuf[0])


## Copies cwd.
proc copyCwd(dst: var array[SysProcessCwdMax, char], src: array[SysProcessCwdMax, char]) =
  copyChars(dst, src)


## Clears ipc queue.
proc clearIpcQueue(p: ptr Process) =
  p.ipc.head = 0
  p.ipc.tail = 0
  p.ipc.count = 0

  var i = 0
  while i < SysIpcQueueCap:
    p.ipc.queue[i] = SysIpcPacket()
    inc i


## Implements the signal bit kernel helper.
proc signalBit(signal: U32): U32 =
  if signal == SysSignalNone or signal > SysSignalMax:
    return U32(0)

  U32(1'u32 shl signal)


## Implements the pipe next kernel helper.
proc pipeNext(index: U32): U32 =
  (index + 1) mod SysPipeBufSize


## Returns whether pipe id is valid.
proc validPipeId(pipeId: I32): bool =
  pipeId >= 0 and pipeId < I32(SysPipeMax) and pipes[U32(pipeId)].used


## Allocates pipe.
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


## Frees pipe.
proc freePipe*(pipeId: I32) =
  if validPipeId(pipeId):
    pipes[U32(pipeId)] = PipeState()


## Retains fd entry.
proc retainFdEntry*(entry: FdEntry) =
  if entry.used and entry.kind == SysFdKindPipe and validPipeId(entry.pipeId):
    if (entry.flags and SysOpenRead) != 0:
      inc pipes[U32(entry.pipeId)].readers
    if (entry.flags and SysOpenWrite) != 0:
      inc pipes[U32(entry.pipeId)].writers


## Releases fd entry.
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


## Implements the pipe read kernel kernel helper.
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


## Implements the pipe write kernel kernel helper.
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


## Implements the pipe readable kernel helper.
proc pipeReadable*(pipeId: I32): bool =
  if not validPipeId(pipeId):
    return false

  let pipe = addr pipes[U32(pipeId)]
  pipe.count > 0 or pipe.writers == 0


## Implements the pipe writable kernel helper.
proc pipeWritable*(pipeId: I32): bool =
  if not validPipeId(pipeId):
    return false

  let pipe = addr pipes[U32(pipeId)]
  pipe.readers > 0 and pipe.count < SysPipeBufSize


## Clears file state.
proc clearFileState*(p: ptr Process) =
  var i = U32(0)
  while i < SysFdMax:
    releaseFdEntry(p.files.entries[i])
    inc i

  p.files = FileState()


## Sets fd path.
proc setFdPath(entry: var FdEntry, path: cstring) =
  var i = U32(0)
  while i < SysFdPathMax - 1 and path != nil and path[i] != '\0':
    entry.path[i] = path[i]
    inc i

  while i < SysFdPathMax:
    entry.path[i] = '\0'
    inc i


## Initializes standard files.
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


## Copies file state.
proc copyFileState(dst, src: ptr Process) =
  dst.files = src.files
  var i = U32(0)
  while i < SysFdMax:
    retainFdEntry(dst.files.entries[i])
    inc i


## Clears user state.
proc clearUserState(p: ptr Process) =
  if p == nil:
    return

  p.user = UserState()


## Returns the mapped heap page count for a user state.
proc heapPageCount*(user: UserState): U64 =
  if user.heapEnd <= user.heapStart:
    return U64(0)

  alignUp(user.heapEnd - user.heapStart, PageSize) div PageSize


## Clears wait.
proc clearWait*(p: ptr Process) =
  if p == nil:
    return

  p.wait = WaitTarget()


## Puts the current process to sleep for current for.
proc sleepCurrentFor(kind: WaitKind, value: U64) =
  if currentProc == nil:
    return

  currentProc.wait.kind = kind
  currentProc.wait.value = value
  currentProc.state = procSleeping
  schedule()
  deliverCurrentSignals()


## Wakes processes waiting for waiters.
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
  setIdentity(p, RootUid, RootGid)
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
  p.user.heapLimit =
    if stackPages == U64(0):
      p.user.heapStart
    else:
      userStackTop - stackPages * PageSize
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
  var i = 0
  while i < MaxProcs:
    if procs[i].state == procSleeping and procs[i].wait.kind == waitPoll:
      clearWait(addr procs[i])
      procs[i].state = procRunnable
    inc i


## Wakes processes waiting for input waiters.
proc wakeInputWaiters*() =
  wakeWaiters(waitInput, 1, true)
  wakePollWaiters()


## Wakes processes waiting for ipc waiter.
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
  var i = 0
  while i < MaxProcs:
    if procs[i].state == procSleeping and
        (procs[i].wait.kind == waitTimer or procs[i].wait.kind == waitPoll) and
        procs[i].wait.value <= tick:
      clearWait(addr procs[i])
      procs[i].state = procRunnable
    inc i


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


## Runs the initial trampoline for a newly scheduled process.
proc processBootstrap*() =
  if currentProc == nil or currentProc.entry == nil:
    panic("invalid current process")

  currentProc.entry()
  currentProc.state = procZombie
  schedule()
  panic("zombie process resumed")


## Selects the next runnable process and switches to it.
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


## Yields the current process to the scheduler.
proc yieldCpu*() =
  if currentProc == nil and not hasRunnableProcess():
    return

  if currentProc != nil and currentProc.state == procRunning:
    currentProc.state = procRunnable

  schedule()
