import ../arch/riscv64/arch
import ../kernel/console
import ../kernel/memory
import ../lib/types

const
  MaxProcs* = 16
  KernelStackPages* = U64(1)

type
  ProcessState* = enum
    procUnused = 0
    procRunnable
    procRunning
    procSleeping
    procZombie

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
    exePath*: cstring
    state*: ProcessState
    context*: Context
    entry*: KernelTask
    kernelStack*: PAddr
    isUser*: bool
    userPc*: VAddr
    userSp*: VAddr
    userArg0*: U64
    userArg1*: U64
    waitingForInput*: bool
    waitingForPid*: int32
    exitStatus*: U64


var
  procs*: array[MaxProcs, Process]
  currentProc*: ptr Process
  nextPid = int32(1)
  needResched {.volatile.}: bool
  idleProc: ptr Process


proc contextSwitch(prev: ptr Context, next: ptr Context) {.importc: "context_switch", cdecl.}
proc processBootstrap*() {.exportc: "process_bootstrap", cdecl.}
proc schedule*()
proc yieldCpu*()
proc maybeYieldOnResched*()
proc printProcessState*(state: ProcessState)
proc sleepCurrentForInput*()
proc sleepCurrentForPid*(pid: int32)
proc wakeInputWaiters*()
proc wakePidWaiters*(pid: int32)


proc findUnusedProc(): ptr Process =
  var i = 0
  while i < MaxProcs:
    if procs[i].state == procUnused:
      return addr procs[i]
    inc i
  nil

proc idleTask() {.cdecl.} =
  while true:
    maybeYieldOnResched()
    arch.writeSstatus(arch.readSstatus() or SstatusSie)
    arch.wfi()

proc createKernelProcessInternal(entry: KernelTask, isIdle: bool): int32 =
  let p = findUnusedProc()
  if p == nil or entry == nil:
    return -1

  let stack = palloc(KernelStackPages)
  if stack == NilPAddr:
    return -1

  p.pid = nextPid
  inc nextPid
  p.state = procRunnable
  p.entry = entry
  p.kernelStack = stack
  p.isUser = false
  p.userPc = 0
  p.userSp = 0
  p.userArg0 = 0
  p.userArg1 = 0
  p.waitingForInput = false
  p.waitingForPid = 0
  p.exitStatus = 0
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
    procs[i].exePath = "init_proc"
    procs[i].state = procUnused
    procs[i].context = Context()
    procs[i].entry = nil
    procs[i].kernelStack = NilPAddr
    procs[i].isUser = false
    procs[i].userPc = 0
    procs[i].userSp = 0
    procs[i].userArg0 = 0
    procs[i].userArg1 = 0
    procs[i].waitingForInput = false
    procs[i].waitingForPid = 0
    procs[i].exitStatus = 0
    inc i

  currentProc = nil
  nextPid = 1
  needResched = false
  idleProc = nil

  if createKernelProcessInternal(idleTask, true) < 0:
    panic("failed to create idle task")

proc createKernelProcess*(entry: KernelTask): int32 =
  createKernelProcessInternal(entry, false)

proc userProcessBootstrap() {.cdecl, noreturn.} =
  if currentProc == nil or not currentProc.isUser:
    panic("invalid user process")

  let kernelSp = currentProc.kernelStack + KernelStackPages * PageSize
  arch.enterUser(currentProc.userPc, currentProc.userSp, kernelSp, currentProc.userArg0, currentProc.userArg1)

proc createUserProcess*(path: cstring, userPc, userSp: VAddr, arg0: U64 = 0, arg1: U64 = 0): int32 =
  let pid = createKernelProcessInternal(userProcessBootstrap, false)
  if pid < 0:
    return pid

  var i = 0
  while i < MaxProcs:
    if procs[i].pid == pid:
      procs[i].exePath = path
      procs[i].isUser = true
      procs[i].userPc = userPc
      procs[i].userSp = userSp
      procs[i].userArg0 = arg0
      procs[i].userArg1 = arg1
      return pid
    inc i

  -1

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
  if currentProc == nil:
    return

  currentProc.waitingForInput = true
  currentProc.state = procSleeping
  schedule()

proc sleepCurrentForPid*(pid: int32) =
  if currentProc == nil:
    return

  currentProc.waitingForPid = pid
  currentProc.state = procSleeping
  schedule()

proc wakeInputWaiters*() =
  var i = 0
  while i < MaxProcs:
    if procs[i].state == procSleeping and procs[i].waitingForInput:
      procs[i].waitingForInput = false
      procs[i].state = procRunnable
    inc i

proc wakePidWaiters*(pid: int32) =
  var i = 0
  while i < MaxProcs:
    if procs[i].state == procSleeping and procs[i].waitingForPid == pid:
      procs[i].waitingForPid = 0
      procs[i].state = procRunnable
    inc i

proc maybeYieldOnResched*() =
  if not needResched:
    return

  needResched = false
  yieldCpu()

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
    if prev != nil:
      prev.state = procRunning
      currentProc = prev
      return

    panic("no runnable process")

  next.state = procRunning
  currentProc = next
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
