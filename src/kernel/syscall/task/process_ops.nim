import ../../../lib/syscall_types
import ../../../lib/types
import ../../dev/console
import ../../fs/fs
import ../../mm/usercopy
import ../../task/exec
import ../../task/process

var
  processEntries: array[MaxProcs, SysProcessInfo]
  pathBuf: array[UserCStringMax, char]
  argBuf: array[UserCStringMax, char]


proc processStateValue(state: ProcessState): U32 =
  case state
  of procUnused: SysProcessUnused
  of procRunnable: SysProcessRunnable
  of procRunning: SysProcessRunning
  of procSleeping: SysProcessSleeping
  of procZombie: SysProcessZombie


proc copyProcessName(dst: var array[SysProcessNameMax, char], src: cstring) =
  var i = 0
  while i < SysProcessNameMax - 1:
    if src == nil or src[i] == '\0':
      break
    dst[i] = src[i]
    inc i
  dst[i] = '\0'


proc syscallPs*(outEntries: U64, maxEntries: U64): U64 =
  if outEntries == 0 or maxEntries == 0:
    return U64(-1'i64)

  var count = U64(0)
  var i = 0
  while i < MaxProcs and count < maxEntries:
    if procs[i].state != procUnused:
      processEntries[count].pid = procs[i].pid
      processEntries[count].ppid = procs[i].parentPid
      processEntries[count].state = processStateValue(procs[i].state)
      if procs[i].user.active:
        processEntries[count].isUser = 1
      else:
        processEntries[count].isUser = 0
      copyProcessName(processEntries[count].exePath, procs[i].exePath)
      inc count
    inc i

  let bytes = count * U64(sizeof(SysProcessInfo))
  if copyToUser(outEntries, addr processEntries[0], bytes) != 0:
    return U64(-1'i64)

  count


proc syscallExit*(status: U64): U64 =
  if currentProc == nil:
    panic("exit without current process")

  currentProc.exitStatus = status
  currentProc.state = procZombie
  wakePidWaiters(currentProc.pid)
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
  let pid = int32(pidVal)
  var target = findProcByPid(pid)
  if target == nil:
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
    return U64(-1'i64)

  let copiedArg =
    if arg == 0:
      nil
    else:
      if copyUserCString(addr argBuf[0], arg, UserCStringMax) < 0:
        return U64(-1'i64)
      cast[cstring](addr argBuf[0])

  U64(execUserApp(cast[cstring](addr pathBuf[0]), copiedArg, detachedVal != 0))


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
  if copyToUser(outBuf, addr cwd[0], i + 1) != 0:
    return U64(-1'i64)

  i


proc setCurrentCwd(path: cstring): int =
  var i = 0
  while i < SysProcessCwdMax - 1 and path[i] != '\0':
    currentProc.cwd[i] = path[i]
    inc i

  if path[i] != '\0':
    return -1

  currentProc.cwd[i] = '\0'
  0


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
  if not fsIsDir(path):
    return U64(-1'i64)
  if setCurrentCwd(path) != 0:
    return U64(-1'i64)

  0


proc syscallGetPid*(outBuf: U64): U64 =
  if currentProc == nil:
    panic("getpid without current process")
  
  let pid = currentProc.pid
  if copyToUser(outBuf, addr pid, U64(sizeof(pid))) != 0:
    return U64(-1'i64)

  0