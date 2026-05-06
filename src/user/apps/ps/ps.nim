import ../../lib/io
import ../../lib/syscall

const
  PsMaxEntries = 16

var
  entries: array[PsMaxEntries, SysProcessInfo]
  services: array[8, SysServiceInfo]
  requestPacket: SysIpcPacket
  responsePacket: SysIpcPacket


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
  let count = sysServiceList(addr services[0], U64(len(services)))
  if count < 0:
    return -1

  var i = I32(0)
  while i < count:
    if services[i].kind == SysServiceKindProcess and services[i].available != 0:
      return services[i].pid
    inc i

  -1


proc copyPacketToProcess(entry: ptr SysProcessInfo, packet: ptr SysIpcPacket) =
  let dst = cast[ptr UncheckedArray[char]](entry)
  var i = 0
  while i < sizeof(SysProcessInfo):
    dst[i] = packet.data[i]
    inc i


proc requestProcessList(maxEntries: I32): I32 =
  let pid = processManagerPid()
  if pid <= 0:
    return -1

  requestPacket = SysIpcPacket()
  requestPacket.op = SysIpcOpProcListRequest
  requestPacket.arg0 = U64(maxEntries)
  if sysIpcSendPacket(pid, addr requestPacket) != 0:
    return -1

  if sysIpcReceivePacket(addr responsePacket) != 0:
    return -1
  if responsePacket.op != SysIpcOpProcListResponse:
    return -1
  if I32(responsePacket.arg0) < 0:
    return -1

  let count = I32(responsePacket.arg0)
  var i = I32(0)
  while i < count and i < maxEntries:
    if sysIpcReceivePacket(addr responsePacket) != 0:
      return -1
    if responsePacket.op != SysIpcOpProcListEntry:
      return -1
    if I32(responsePacket.arg0) < 0 or I32(responsePacket.arg0) >= maxEntries:
      return -1

    copyPacketToProcess(addr entries[I32(responsePacket.arg0)], addr responsePacket)
    inc i

  count


proc user_start*(arg: cstring) {.exportc, cdecl, noreturn.} =
  discard arg

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
