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
import ../syscall_cap

var
  processEntries: array[MaxProcs, SysProcessInfo]
  pathBuf: array[UserCStringMax, char]
  argBuf: array[UserCStringMax, char]
  cwdCheckEntries: array[2, FsDirEntry]


proc processStateValue(state: ProcessState): U32 =
  case state
  of procUnused: SysProcessUnused
  of procRunnable: SysProcessRunnable
  of procRunning: SysProcessRunning
  of procSleeping: SysProcessSleeping
  of procZombie: SysProcessZombie


proc fillProcessInfo(entry: var SysProcessInfo, p: ptr Process) =
  entry = SysProcessInfo()
  entry.pid = p.pid
  entry.ppid = p.parentPid
  entry.uid = p.identity.uid
  entry.gid = p.identity.gid
  entry.state = processStateValue(p.state)
  entry.cpuTicks = p.cpuTicks
  entry.memoryPages =
    if p.user.active:
      p.user.imagePages + p.user.stackPages + KernelStackPages
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
  entry.requestedCapabilityMask = p.user.requestedCapabilityMask
  entry.capabilityMask = p.user.capabilityMask
  entry.pendingSignals = p.pendingSignals
  if p.user.active:
    entry.isUser = 1
  else:
    entry.isUser = 0
  discard copyCString(entry.exePath, p.exePath)


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


proc syscallExit*(status: U64): U64 =
  if currentProc == nil:
    panic("exit without current process")

  markProcessZombie(currentProc, status)
  schedule()
  0


proc findProcByPid(pid: int32): ptr Process =
  var i = 0
  while i < MaxProcs:
    if procs[i].state != procUnused and procs[i].pid == pid:
      return addr procs[i]
    inc i
  nil


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


proc setCurrentCwd(path: cstring): int =
  if copyCString(currentProc.cwd, path):
    0
  else:
    -1


proc servicePathIsDir(path: cstring): bool =
  let count = serviceLsToKernel(path, addr cwdCheckEntries[0], U64(cwdCheckEntries.len))
  if count < 2:
    return false

  cwdCheckEntries[0].typ == FsDirEntryTypeDir and
    cwdCheckEntries[1].typ == FsDirEntryTypeDir and
    fixedCStringEq(cwdCheckEntries[0].name, ".") and
    fixedCStringEq(cwdCheckEntries[1].name, "..")


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

  0


proc syscallGetPid*(): U64 =
  if currentProc == nil:
    return U64(-1'i64)
  
  U64(currentProc.pid)


proc syscallGetPpid*(): U64 =
  if currentProc == nil:
    return U64(-1'i64)

  U64(currentProc.parentPid)


proc syscallGetUid*(): U64 =
  if currentProc == nil:
    return U64(-1'i64)

  U64(currentProc.identity.uid)


proc syscallGetGid*(): U64 =
  if currentProc == nil:
    return U64(-1'i64)

  U64(currentProc.identity.gid)


proc syscallLastError*(): U64 =
  if currentProc == nil:
    return U64(SysErrInval)

  U64(currentProc.lastError)


proc syscallSetUser*(uidVal, gidVal: U64): U64 =
  if currentProc == nil:
    return U64(-1'i64)

  let uid = U32(uidVal)
  let gid = U32(gidVal)
  if currentProc.identity.uid != RootUid and not cstringEq(currentProc.exePath, cstring"/bin/shell"):
    setLastError(SysErrPerm)
    return U64(-2'i64)

  currentProc.identity.uid = uid
  currentProc.identity.gid = gid
  clearLastError()
  0


proc syscallGetCap*(outBuf, bufSize: U64): U64 =
  if currentProc == nil:
    return U64(-1'i64)

  if copyToUser(outBuf, addr currentProc.user.capabilityMask, bufSize) != 0:
    return U64(-1'i64)

  0


proc syscallSignalPoll*(outSignal: U64): U64 =
  if currentProc == nil or outSignal == 0:
    return U64(-1'i64)

  var signal = takeProcessSignal(currentProc)
  if copyToUser(outSignal, addr signal, U64(sizeof(U32))) != 0:
    return U64(-1'i64)

  if signal == SysSignalTerminate or signal == SysSignalInterrupt:
    return U64(1)

  0
