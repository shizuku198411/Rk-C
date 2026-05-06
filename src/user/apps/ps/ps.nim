import ../../lib/io
import ../../lib/syscall

const
  PsMaxEntries = 16


proc stateName(state: U32): cstring =
  if state == SysProcessRunnable:
    "runnable"
  elif state == SysProcessRunning:
    "running "
  elif state == SysProcessSleeping:
    "sleeping"
  elif state == SysProcessZombie:
    "zombie  "
  else:
    "unused  "


proc modeName(isUser: U32): cstring =
  if isUser != 0:
    "user"
  else:
    "kernel"


proc printProcess(entry: ptr SysProcessInfo) =
  writeUnsigned(U64(entry.pid))
  write("\t")
  writeUnsigned(U64(entry.ppid))
  write("\t")
  write(stateName(entry.state))
  write("\t")
  write(modeName(entry.isUser))
  write("\t")
  write(cast[cstring](addr entry.exePath[0]))
  write("\n")


proc sortProcesByPid(entries: var array[PsMaxEntries, SysProcessInfo], count: I32) =
  var i = 1

  while i < count:
    let key = entries[i]
    var j = i
    
    while j > 0 and entries[j - 1].pid > key.pid:
      entries[j] = entries[j - 1]
      dec j
    
    entries[j] = key
    inc i


proc user_start*(arg: cstring) {.exportc, cdecl, noreturn.} =
  discard arg

  var entries: array[PsMaxEntries, SysProcessInfo]
  let count = sysPs(addr entries[0], U64(PsMaxEntries))
  if count < 0:
    write("ps: failed\n")
    sysExit(1)

  sortProcesByPid(entries, count)

  write("pid\tppid\tstate\t\tmode\texe\n")
  var i = 0
  while i < int(count):
    printProcess(addr entries[i])
    inc i

  sysExit(0)
