## Implements process state, scheduling, waits, fd state, pipes, and signals.
import ../../arch/riscv64/arch
import ../../lib/calc
import ../../lib/fixed_string
import ../../lib/syscall_types
import ../../lib/types
import ../../lib/user_ids
import ../dev/console
import ../dev/tty
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
    waitTtyRead
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
    pipeGeneration*: U32
    ttyId*: I32
    path*: array[SysFdPathMax, char]

  FileState* {.bycopy.} = object
    entries*: array[SysFdMax, FdEntry]

  ProcessIdentity* {.bycopy.} = object
    uid*: U32
    gid*: U32

  PipeState* {.bycopy.} = object
    used*: bool
    generation*: U32
    readers*: U32
    writers*: U32
    head*: U32
    tail*: U32
    count*: U32
    data*: array[SysPipeBufSize, U8]
  
  EnvEntry* {.bycopy.} = object
    used*: bool
    key*: array[SysEnvKeyMax, char]
    value*: array[SysEnvValueMax, char]
  
  EnvState* {.bycopy.} = object
    entries*: array[SysEnvMaxEntries, EnvEntry]

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
    env*: EnvState


var
  procs*: array[MaxProcs, Process]
  currentProc*: ptr Process
  nextPid = int32(1)
  needResched {.volatile.}: bool
  idleProc: ptr Process
  kernelPageTable: PageTable
  pipes: array[SysPipeMax, PipeState]
  nextPipeGeneration: U32

  # Cached wait state
  waitKindMasks: array[WaitKind, U64]
  nextTimerWakeTick: U64


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
## Puts the current process to sleep while waiting for TTY input.
proc sleepCurrentForTtyRead*(ttyId: I32)
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
proc sleepCurrentForPipeRead*(pipeId: I32, pipeGeneration: U32)
## Puts the current process to sleep for current for pipe write.
proc sleepCurrentForPipeWrite*(pipeId: I32, pipeGeneration: U32)
## Puts the current process to sleep for current for poll.
proc sleepCurrentForPoll*(deadlineTick: U64)
## Wakes processes waiting to read from a TTY.
proc wakeTtyReaders*(ttyId: I32)
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
proc wakePipeReaders*(pipeId: I32, pipeGeneration: U32)
## Wakes processes waiting for pipe writers.
proc wakePipeWriters*(pipeId: I32, pipeGeneration: U32)
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


## Sets root user cwd.
proc setRootUserCwd(p: ptr Process) =
  discard copyCString(p.cwd, cstring"/root")


## Sets default cwd for identity.
proc setDefaultCwdForIdentity(p: ptr Process, uid: U32) =
  if p == nil:
    return

  if uid == RootUid:
    setRootUserCwd(p)
  else:
    setRootCwd(p)


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


## Clears process environment variables.
proc clearEnv(p: ptr Process) =
  if p == nil:
    return

  var i = U32(0)
  while i < SysEnvMaxEntries:
    p.env.entries[i] = EnvEntry()
    inc i


## Finds a process environment entry by id.
proc findEnvEntry(p: ptr Process, key: cstring): I32 =
  if p == nil or key == nil:
    return I32(-1)

  var i = U32(0)
  while i < SysEnvMaxEntries:
    if p.env.entries[i].used and fixedCStringEq(p.env.entries[i].key, key):
      return I32(i)
    inc i
  
  I32(-1)


## Finds a free process environment entry.
proc findFreeEnvEntry(p: ptr Process): I32 =
  if p == nil:
    return I32(-1)

  var i = U32(0)
  while i < SysEnvMaxEntries:
    if not p.env.entries[i].used:
      return I32(i)
    inc i
  
  I32(-1)


## Sets or updates one process environment variable.
proc setEnv*(p: ptr Process, key, value: cstring, overwrite: bool = true): bool =
  if p == nil or key == nil or value == nil or key[0] == '\0':
    return false

  var idx = findEnvEntry(p, key)
  if idx >= 0:
    if not overwrite:
      return false
  else:
    idx = findFreeEnvEntry(p)
    if idx < 0:
      return false
    p.env.entries[U32(idx)].used = true
    if not copyCString(p.env.entries[U32(idx)].key, key):
      p.env.entries[U32(idx)] = EnvEntry()
      return false
  
  if not copyCString(p.env.entries[U32(idx)].value, value):
    if p.env.entries[U32(idx)].key[0] == '\0':
      p.env.entries[U32(idx)] = EnvEntry()
    return false

  true


## Removes one process environment variable.
proc unsetEnv*(p: ptr Process, key: cstring): bool =
  let idx = findEnvEntry(p, key)
  if idx < 0:
    return false

  p.env.entries[U32(idx)] = EnvEntry()
  true


## Copies process environment variables.
proc copyEnv(dst, src: ptr Process) =
  if dst == nil:
    return

  if src == nil:
    clearEnv(dst)
    return

  dst.env = src.env


## Sets the PED environment variables from the process cwd.
proc syncPwdEnv*(p: ptr Process) =
  if p == nil:
    return

  discard setEnv(p, cstring("PWD"), cast[cstring](addr p.cwd[0]))


## Install default environment variables for an identity.
proc initDefaultEnvForIdentity*(p: ptr Process, uid, gid: U32) =
  if p == nil:
    return

  clearEnv(p)
  discard setEnv(p, cstring("PATH"), cstring("/bin"))
  discard setEnv(p, cstring("SHELL"), cstring("/bin/shell"))
  discard setEnv(p, cstring("TERM"), cstring("uart"))
  if uid == RootUid:
    discard setEnv(p, cstring("HOME"), cstring("/root"))
  else:
    discard setEnv(p, cstring("HOME"), cstring("/home/rkc"))
  discard setEnv(p, cstring("PWD"), cast[cstring](addr p.cwd[0]))


## Implements the signal bit kernel helper.
proc signalBit(signal: U32): U32 =
  if signal == SysSignalNone or signal > SysSignalMax:
    return U32(0)

  U32(1'u32 shl signal)


## Includes implements process file-descriptor state and in-kernel pipe storage.
include ./internal/io_state


## Includes creates, configures, inherits, and tears down processes and user mappings.
include ./internal/lifecycle


## Includes coordinates sleeping, waking, exit delivery, signals, and reschedule requests.
include ./internal/wait_signals


## Includes runs process entry trampolines and performs scheduling and cpu yields.
include ./internal/scheduler
