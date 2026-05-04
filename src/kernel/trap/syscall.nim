import ../../lib/syscall_ids
import ../../lib/types
import ../dev/console
import ../dev/rtc
import ../dev/timer
import ../fs/dirent
import ../fs/fs
import ../task/exec
import ../task/process
import ../trap/trap_types

proc sbiShutdown() {.importc: "sbi_shutdown", cdecl.}

proc syscallWrite(buf: U64, len: U64): U64 =
  let p = cast[ptr UncheckedArray[char]](buf)
  var i = U64(0)
  while i < len:
    putChar(p[i])
    inc i
  len


proc syscallRead(buf: U64, len: U64): U64 =
  if len == 0:
    return 0

  let p = cast[ptr UncheckedArray[char]](buf)
  var i = U64(0)
  while i < len:
    let ch = tryGetChar()
    if ch < 0:
      sleepCurrentForInput()
      continue

    p[i] = char(ch and 0xff)
    inc i
  i


proc syscallPs(): U64 =
  println("pid\tstate\t\tmode\texe")

  var i = 0
  while i < MaxProcs:
    if procs[i].state != procUnused:
      printUnsigned(U64(procs[i].pid))
      putChar('\t')
      printProcessState(procs[i].state)
      putChar('\t')
      if procs[i].isUser:
        print("user")
      else:
        print("kernel")
      putChar('\t')
      print(procs[i].exePath)
      putChar('\n')
    inc i

  0

proc syscallExit(status: U64): U64 =
  if currentProc == nil:
    panic("exit without current process")

  currentProc.exitStatus = status
  currentProc.state = procZombie
  wakePidWaiters(currentProc.pid)
  schedule()
  0


proc syscallShutdown() =
  sbiShutdown()


proc findProcByPid(pid: int32): ptr Process =
  var i = 0
  while i < MaxProcs:
    if procs[i].state != procUnused and procs[i].pid == pid:
      return addr procs[i]
    inc i
  nil


proc syscallWait(pidVal: U64): U64 =
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
  target.state = procUnused
  status


proc syscallGetDateTime(): U64 =
  print(nowCString())
  putChar('\n')
  0


proc handleSyscall*(frame: ptr TrapFrame) =
  case frame.a3
  of SysWrite:
    frame.a0 = syscallWrite(frame.a0, frame.a1)
  
  of SysRead:
    frame.a0 = syscallRead(frame.a0, frame.a1)
  
  of SysPs:
    frame.a0 = syscallPs()
  
  of SysTicks:
    frame.a0 = timerTickCount
  
  of SysExit:
    frame.a0 = syscallExit(frame.a0)
  
  of SysLs:
    let path =
      if frame.a0 == 0: cstring("/")
      else: cast[cstring](frame.a0)
    frame.a0 = U64(fsReadDirEntries(path, cast[ptr FsDirEntry](frame.a1), frame.a2))
  
  of SysCat:
    frame.a0 = U64(fsCat(cast[cstring](frame.a0)))
  
  of SysMkdir:
    frame.a0 = U64(fsMkdir(cast[cstring](frame.a0)))
  
  of SysExec:
    frame.a0 = U64(execUserApp(cast[cstring](frame.a0), cast[cstring](frame.a1)))
  
  of SysWait:
    frame.a0 = syscallWait(frame.a0)
  
  of SysUnlink:
    frame.a0 = U64(fsUnlink(cast[cstring](frame.a0)))
  
  of SysRmdir:
    frame.a0 = U64(fsRmdir(cast[cstring](frame.a0)))
  
  of SysShutdown:
    syscallShutdown()
  
  of SysGetDateTime:
    frame.a0 = U64(syscallGetDateTime())
  
  else:
    print("PANIC: unknown syscall ")
    printUnsigned(frame.a3)
    putChar('\n')
    while true:
      discard
