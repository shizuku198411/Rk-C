import ../../lib/core/io
import ../../lib/ipc/packet_data
import ../../lib/ipc/ipc_request
import ../../lib/ipc/service_client
import ../../lib/core/args
import ../../lib/core/strutils
import ../../lib/core/syscall

const
  PsMaxEntries = 16

var
  entries: array[PsMaxEntries, SysProcessInfo]
  requestPacket: SysIpcPacket
  responsePacket: SysIpcPacket
  parsedArgs: UserArgs


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


proc processManagerPid(): I32 =
  servicePidByKind(SysServiceKindProcess)


proc copyPacketToProcess(entry: ptr SysProcessInfo, packet: ptr SysIpcPacket) =
  discard copyFromPacketData(entry, packet, U32(sizeof(SysProcessInfo)))


proc requestProcessList(maxEntries: I32): I32 =
  let pid = processManagerPid()
  if pid <= 0:
    return -1

  requestPacket = SysIpcPacket()
  requestPacket.op = SysIpcOpProcListRequest
  requestPacket.arg0 = U64(maxEntries)
  if requestIpcReply(pid, addr requestPacket, addr responsePacket, SysIpcOpProcListResponse) != 0:
    return -1

  let count = I32(responsePacket.arg0)
  if count < 0:
    return -1

  var i = I32(0)
  while i < count and i < maxEntries:
    if receiveIpcReply(pid, addr responsePacket, SysIpcOpProcListEntry) != 0:
      return -1
    if I32(responsePacket.arg0) < 0 or I32(responsePacket.arg0) >= maxEntries:
      return -1

    copyPacketToProcess(addr entries[I32(responsePacket.arg0)], addr responsePacket)
    inc i

  count


proc printUsage() =
  write("usage: ps\n")


proc user_start*(arg: cstring) {.exportc, cdecl, noreturn.} =
  if not parseUserArgs(arg, parsedArgs):
    printUsage()
    sysExit(1)

  if parsedArgs.argc == 1 and streq(argAt(parsedArgs, 0), "--help"):
    printUsage()
    sysExit(0)

  if parsedArgs.argc != 0:
    printUsage()
    sysExit(1)

  let count = requestProcessList(PsMaxEntries)
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
