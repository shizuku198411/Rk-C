## Implements process, exec, cwd, identity, and signal syscall handlers.
import ../../../lib/fixed_string
import ../../../lib/syscall_types
import ../../../lib/types
import ../../../lib/user_ids
import ../../dev/console
import ../../fs/dirent
import ../../fs/fs
import ../../lib/syscall_out
import ../../mm/usercopy
import ../../task/exec
import ../../task/process
import ../fs/fs_service_ops
import ../scratch
import ../syscall_cap

template processEntries: untyped = processScratch.processEntries
template pathBuf: untyped = processScratch.pathBuf
template argBuf: untyped = processScratch.argBuf
template envEntries: untyped = processScratch.envEntries
template envKeyBuf: untyped = processScratch.envKeyBuf
template envValueBuf: untyped = processScratch.envValueBuf
template cwdCheckEntries: untyped = processScratch.cwdCheckEntries
template fdInfoEntries: untyped = processScratch.fdInfoEntries


## Implements the process state value kernel helper.
proc processStateValue(state: ProcessState): U32 =
  case state
  of procUnused: SysProcessUnused
  of procRunnable: SysProcessRunnable
  of procRunning: SysProcessRunning
  of procSleeping: SysProcessSleeping
  of procZombie: SysProcessZombie


## Implements the wait target value kernel helper.
proc waitKindValue(kind: WaitKind): U32 =
  case kind
  of waitNone: SysWaitNone
  of waitTtyRead: SysWaitTtyRead
  of waitIpc: SysWaitIpc
  of waitPid: SysWaitPid
  of waitFsReq: SysWaitFsReq
  of waitBlockReq: SysWaitBlockReq
  of waitTimer: SysWaitTimer
  of waitPipeRead: SysWaitPipeRead
  of waitPipeWrite: SysWaitPipeWrite
  of waitPoll: SysWaitPoll


## Fills process info.
proc fillProcessInfo(entry: var SysProcessInfo, p: ptr Process) =
  entry = SysProcessInfo()
  entry.pid = p.pid
  entry.ppid = p.parentPid
  entry.uid = p.identity.uid
  entry.gid = p.identity.gid
  entry.state = processStateValue(p.state)
  entry.cpuTicks = p.cpuTicks
  let heapPages =
    if p.user.active:
      heapPageCount(p.user)
    else:
      U64(0)
  entry.memoryPages =
    if p.user.active:
      p.user.imagePages + p.user.stackPages + heapPages + KernelStackPages
    elif p.kernelStack != NilPAddr:
      KernelStackPages
    else:
      U64(0)
  entry.cpuPercent = p.cpuPercent
  entry.textVa = p.user.textVa
  entry.textMemSize = p.user.textMemSize
  entry.rodataVa = p.user.rodataVa
  entry.rodataMemSize = p.user.rodataMemSize
  entry.dataVa = p.user.dataVa
  entry.dataMemSize = p.user.dataMemSize
  entry.bssVa = p.user.bssVa
  entry.bssMemSize = p.user.bssMemSize
  entry.stackTop = p.user.stackTop
  entry.stackPages = p.user.stackPages
  entry.heapStart = p.user.heapStart
  entry.heapPages = heapPages
  entry.requestedCapabilityMask = p.user.requestedCapabilityMask
  entry.capabilityMask = p.user.capabilityMask
  entry.pendingSignals = p.pendingSignals
  entry.waitKind = waitKindValue(p.wait.kind)
  entry.waitValue = p.wait.value
  if p.user.active:
    entry.isUser = 1
  else:
    entry.isUser = 0
  discard copyCString(entry.exePath, p.exePath)


## Fills environment info.
proc fillEnvInfo(entry: var SysEnvEntry, src: EnvEntry) =
  entry = SysEnvEntry()
  if not src.used:
    return

  entry.used = U32(1)
  copyChars(entry.key, src.key)
  copyChars(entry.value, src.value)


## Handles the ps syscall operation.
proc syscallPs*(outEntries: U64, maxEntries: U64, flags: U64 = 0): U64 =
  if not canSyscallProcessList():
    return U64(-1'i64)
  if outEntries == 0 or maxEntries == 0:
    return U64(-1'i64)

  let includeUnused = (flags and SysProcListAllSlots) != 0
  var count = U64(0)
  var i = 0
  while i < MaxProcs and count < maxEntries:
    if includeUnused or procs[i].state != procUnused:
      fillProcessInfo(processEntries[count], addr procs[i])
      inc count
    inc i

  let bytes = count * U64(sizeof(SysProcessInfo))
  if not copyOutBuffer(outEntries, addr processEntries[0], bytes):
    return U64(-1'i64)

  count


## Handles the exit syscall operation.
proc syscallExit*(status: U64): U64 =
  if currentProc == nil:
    panic("exit without current process")

  markProcessZombie(currentProc, status)
  schedule()
  0


## Finds proc by pid.
proc findProcByPid(pid: int32): ptr Process =
  var i = 0
  while i < MaxProcs:
    if procs[i].state != procUnused and procs[i].pid == pid:
      return addr procs[i]
    inc i
  nil


## Handles the wait syscall operation.
proc syscallWait*(pidVal: U64): U64 =
  if currentProc == nil:
    return U64(-1'i64)

  let pid = int32(pidVal)
  var target = findProcByPid(pid)
  if target == nil:
    return U64(-1'i64)

  if target.parentPid != currentProc.pid:
    return U64(-1'i64)

  while target.state != procZombie:
    sleepCurrentForPid(pid)
    target = findProcByPid(pid)
    if target == nil:
      return U64(-1'i64)

  let status = target.exitStatus
  discardProcess(target)
  status


## Handles the exec syscall operation.
proc syscallExec*(path, arg, detachedVal: U64): U64 =
  if copyUserCString(addr pathBuf[0], path, UserCStringMax) < 0:
    setLastError(SysErrInval)
    return U64(-1'i64)
  if currentProc == nil:
    setLastError(SysErrInval)
    return U64(-1'i64)

  let execStatus = fsExecuteStatus(
    currentProc.identity.uid,
    currentProc.identity.gid,
    cast[cstring](addr pathBuf[0]),
  )
  if execStatus == SysErrNoEnt:
    setLastError(SysErrNoEnt)
    return cast[U64](I64(SysExecNoEntry))
  if execStatus != SysErrOk:
    setLastError(execStatus)
    return cast[U64](I64(SysExecPermission))

  let copiedArg =
    if arg == 0:
      nil
    else:
      if copyUserCString(addr argBuf[0], arg, UserCStringMax) < 0:
        setLastError(SysErrInval)
        return U64(-1'i64)
      cast[cstring](addr argBuf[0])

  let pid = execUserApp(cast[cstring](addr pathBuf[0]), copiedArg, detachedVal != 0)
  if pid == SysExecPermission:
    setLastError(SysErrAccess)
  elif pid == SysExecNoEntry:
    setLastError(SysErrNoEnt)
  elif pid < 0:
    setLastError(SysErrInval)

  if pid < 0:
    return cast[U64](I64(pid))

  U64(pid)


## Handles the exec as syscall operation.
proc syscallExecAs*(path, arg, uidGidVal: U64): U64 =
  if copyUserCString(addr pathBuf[0], path, UserCStringMax) < 0:
    setLastError(SysErrInval)
    return U64(-1'i64)
  if currentProc == nil:
    setLastError(SysErrInval)
    return U64(-1'i64)
  if currentProc.identity.uid != RootUid:
    setLastError(SysErrPerm)
    return cast[U64](I64(SysExecPermission))

  let uid = U32(uidGidVal and U64(0xffffffff'u64))
  let gid = U32((uidGidVal shr U64(32)) and U64(0xffffffff'u64))
  let execStatus = fsExecuteStatus(
    uid,
    gid,
    cast[cstring](addr pathBuf[0]),
  )
  if execStatus == SysErrNoEnt:
    setLastError(SysErrNoEnt)
    return cast[U64](I64(SysExecNoEntry))
  if execStatus != SysErrOk:
    setLastError(execStatus)
    return cast[U64](I64(SysExecPermission))

  let copiedArg =
    if arg == 0:
      nil
    else:
      if copyUserCString(addr argBuf[0], arg, UserCStringMax) < 0:
        setLastError(SysErrInval)
        return U64(-1'i64)
      cast[cstring](addr argBuf[0])

  let pid = execUserAppAs(cast[cstring](addr pathBuf[0]), copiedArg, uid, gid)
  if pid == SysExecPermission:
    setLastError(SysErrAccess)
  elif pid == SysExecNoEntry:
    setLastError(SysErrNoEnt)
  elif pid < 0:
    setLastError(SysErrInval)

  if pid < 0:
    return cast[U64](I64(pid))

  U64(pid)


## Handles the get cwd syscall operation.
proc syscallGetCwd*(outBuf, capacity: U64): U64 =
  if currentProc == nil:
    panic("getcwd without current process")
  if outBuf == 0 or capacity == 0:
    return U64(-1'i64)

  var cwd: array[SysProcessCwdMax, char]
  var i = U64(0)
  while i + 1 < U64(SysProcessCwdMax) and currentProc.cwd[i] != '\0':
    cwd[i] = currentProc.cwd[i]
    inc i

  cwd[i] = '\0'
  if capacity < i + 1:
    return U64(-1'i64)
  if not copyOutBuffer(outBuf, addr cwd[0], i + 1):
    return U64(-1'i64)

  i


## Sets current cwd.
proc setCurrentCwd(path: cstring): int =
  if copyCString(currentProc.cwd, path):
    0
  else:
    -1


## Implements the service path is dir kernel helper.
proc servicePathIsDir(path: cstring): bool =
  let count = serviceLsToKernel(path, addr cwdCheckEntries[0], U64(cwdCheckEntries.len))
  if count < 2:
    return false

  cwdCheckEntries[0].typ == FsDirEntryTypeDir and
    cwdCheckEntries[1].typ == FsDirEntryTypeDir and
    fixedCStringEq(cwdCheckEntries[0].name, ".") and
    fixedCStringEq(cwdCheckEntries[1].name, "..")


## Handles the set cwd syscall operation.
proc syscallSetCwd*(pathVal: U64): U64 =
  if currentProc == nil:
    panic("setcwd without current process")
  if pathVal == 0:
    return U64(-1'i64)

  if copyUserCString(addr pathBuf[0], pathVal, UserCStringMax) < 0:
    return U64(-1'i64)

  let path = cast[cstring](addr pathBuf[0])
  if path[0] != '/':
    return U64(-1'i64)
  if not fsCanSearchDirPath(currentProc.identity.uid, currentProc.identity.gid, path):
    return U64(-1'i64)
  if not servicePathIsDir(path):
    return U64(-1'i64)
  if setCurrentCwd(path) != 0:
    return U64(-1'i64)

  syncPwdEnv(currentProc)
  0


## Handles the get pid syscall operation.
proc syscallGetPid*(): U64 =
  if currentProc == nil:
    return U64(-1'i64)
  
  U64(currentProc.pid)


## Handles the get ppid syscall operation.
proc syscallGetPpid*(): U64 =
  if currentProc == nil:
    return U64(-1'i64)

  U64(currentProc.parentPid)


## Handles the get uid syscall operation.
proc syscallGetUid*(): U64 =
  if currentProc == nil:
    return U64(-1'i64)

  U64(currentProc.identity.uid)


## Handles the get gid syscall operation.
proc syscallGetGid*(): U64 =
  if currentProc == nil:
    return U64(-1'i64)

  U64(currentProc.identity.gid)


## Handles the get environment syscall operation.
proc syscallGetEnv*(outBuf, keyVal: U64): U64 =
  if currentProc == nil:
    setLastError(SysErrInval)
    return U64(-1'i64)
  if outBuf == 0:
    setLastError(SysErrInval)
    return U64(-1'i64)

  if keyVal == 0:
    var count = U64(0)
    var i = U32(0)
    while i < SysEnvMaxEntries:
      if currentProc.env.entries[i].used:
        fillEnvInfo(envEntries[count], currentProc.env.entries[i])
        inc count
      inc i

    let bytes = count * U64(sizeof(SysEnvEntry))
    if not copyOutBuffer(outBuf, addr envEntries[0], bytes):
      setLastError(SysErrInval)
      return U64(-1'i64)

    return count

  if copyUserCString(addr envKeyBuf[0], keyVal, U64(SysEnvKeyMax)) < 0:
    setLastError(SysErrInval)
    return U64(-1'i64)
  if envKeyBuf[0] == '\0':
    setLastError(SysErrInval)
    return U64(-1'i64)

  var i = U32(0)
  while i < SysEnvMaxEntries:
    let entry = addr currentProc.env.entries[i]
    if entry.used and fixedCStringEq(entry.key, cast[cstring](addr envKeyBuf[0])):
      let value = cast[cstring](addr entry.value[0])
      let len = cstrlen(value)
      if not copyOutBuffer(outBuf, addr entry.value[0], len + U64(1)):
        setLastError(SysErrInval)
        return U64(-1'i64)
      return len
    inc i

  setLastError(SysErrNoEnt)
  U64(-1'i64)


## Handles the set environment syscall operation.
proc syscallSetEnv*(key, value: U64): U64 =
  if currentProc == nil:
    setLastError(SysErrInval)
    return U64(-1'i64)
  if key == 0 or value == 0:
    setLastError(SysErrInval)
    return U64(-1'i64)

  if copyUserCString(addr envKeyBuf[0], key, U64(SysEnvKeyMax)) < 0:
    setLastError(SysErrInval)
    return U64(-1'i64)
  if envKeyBuf[0] == '\0':
    setLastError(SysErrInval)
    return U64(-1'i64)

  if copyUserCString(addr envValueBuf[0], value, U64(SysEnvValueMax)) < 0:
    setLastError(SysErrInval)
    return U64(-1'i64)

  var i = U32(0)
  while i < SysEnvMaxEntries:
    let entry = addr currentProc.env.entries[i]
    if entry.used and fixedCStringEq(entry.key, cast[cstring](addr envKeyBuf[0])):
      if envValueBuf[0] == '\0':
        currentProc.env.entries[i] = EnvEntry()
        return 0

      if setEnv(currentProc, cast[cstring](addr envKeyBuf[0]), cast[cstring](addr envValueBuf[0])):
        return 0
      setLastError(SysErrInval)
      return U64(-1'i64)
    inc i

  if envValueBuf[0] == '\0':
    return 0

  if not setEnv(currentProc, cast[cstring](addr envKeyBuf[0]), cast[cstring](addr envValueBuf[0])):
    setLastError(SysErrInval)
    return U64(-1'i64)

  0


## Handles the last error syscall operation.
proc syscallLastError*(): U64 =
  if currentProc == nil:
    return U64(SysErrInval)

  U64(currentProc.lastError)


## Handles the set user syscall operation.
proc syscallSetUser*(uidVal, gidVal: U64): U64 =
  if currentProc == nil:
    return U64(-1'i64)

  let uid = U32(uidVal)
  let gid = U32(gidVal)
  if currentProc.identity.uid != RootUid and
     not cstringEq(currentProc.exePath, cstring"/bin/shell") and
     not cstringEq(currentProc.exePath, cstring"/bin/sudo"):
    setLastError(SysErrPerm)
    return U64(-2'i64)

  currentProc.identity.uid = uid
  currentProc.identity.gid = gid
  initDefaultEnvForIdentity(currentProc, uid, gid)
  clearLastError()
  0


## Handles the get cap syscall operation.
proc syscallGetCap*(outBuf, bufSize: U64): U64 =
  if currentProc == nil:
    return U64(-1'i64)

  if copyToUser(outBuf, addr currentProc.user.capabilityMask, bufSize) != 0:
    return U64(-1'i64)

  0


## Handles the signal poll syscall operation.
proc syscallSignalPoll*(outSignal: U64): U64 =
  if currentProc == nil or outSignal == 0:
    return U64(-1'i64)

  var signal = takeProcessSignal(currentProc)
  if copyToUser(outSignal, addr signal, U64(sizeof(U32))) != 0:
    return U64(-1'i64)

  if signal == SysSignalTerminate or signal == SysSignalInterrupt:
    return U64(1)

  0


proc fillFdInfo(entry: var SysFdInfo, fd: I32, src: FdEntry) =
  entry = SysFdInfo()
  entry.fd = fd

  if not src.used:
    entry.used = 0
    return

  entry.used = 1
  entry.kind = src.kind
  entry.flags  = src.flags
  entry.offset = src.offset
  entry.size = src.size
  entry.pipeId = src.pipeId
  entry.ttyId = src.ttyId
  discard copyCString(entry.path, cast[cstring](addr src.path[0]))


## Handles the fd list syscall operation.
proc syscallFdList*(pidVal, outEntries, maxEntries: U64): U64 =
  if not canSyscallProcessList():
    return U64(-1'i64)
  if outEntries == 0 or maxEntries == 0:
    return U64(-1'i64)

  let
    pid = I32(pidVal)
    target = findProcByPid(pid)
  if target == nil:
    return U64(-1'i64)

  var
    count = U32(0)
    fd = U32(0)
  
  while fd < SysFdMax and count < maxEntries:
    if target.files.entries[fd].used:
      fillFdInfo(fdInfoEntries[count], I32(fd), target.files.entries[fd])
      inc count
    inc fd
  
  let bytes = count * U64(sizeof(SysFdInfo))
  if not copyOutBuffer(outEntries, addr fdInfoEntries[0], bytes):
    return U64(-1'i64)
  
  count
