import ../../../lib/syscall_types
import ../../../lib/types
import ../../dev/console
import ../../fs/fs
import ../../task/exec
import ../../task/process

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

  let entries = cast[ptr UncheckedArray[SysProcessInfo]](outEntries)
  var count = U64(0)
  var i = 0
  while i < MaxProcs and count < maxEntries:
    if procs[i].state != procUnused:
      entries[count].pid = procs[i].pid
      entries[count].ppid = procs[i].parentPid
      entries[count].state = processStateValue(procs[i].state)
      if procs[i].isUser:
        entries[count].isUser = 1
      else:
        entries[count].isUser = 0
      copyProcessName(entries[count].exePath, procs[i].exePath)
      inc count
    inc i

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


proc syscallExec*(path, arg: U64): U64 =
  U64(execUserApp(cast[cstring](path), cast[cstring](arg)))


proc syscallGetCwd*(outBuf, capacity: U64): U64 =
  if currentProc == nil:
    panic("getcwd without current process")
  if outBuf == 0 or capacity == 0:
    return U64(-1'i64)

  let dst = cast[ptr UncheckedArray[char]](outBuf)
  var i = U64(0)
  while i + 1 < capacity and i < U64(SysProcessCwdMax) and currentProc.cwd[i] != '\0':
    dst[i] = currentProc.cwd[i]
    inc i

  dst[i] = '\0'
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

  let path = cast[cstring](pathVal)
  if path[0] != '/':
    return U64(-1'i64)
  if not fsIsDir(path):
    return U64(-1'i64)
  if setCurrentCwd(path) != 0:
    return U64(-1'i64)

  0
