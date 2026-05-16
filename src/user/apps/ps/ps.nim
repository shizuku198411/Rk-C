import ../../lib/core/io
import ../../lib/ipc/packet_data
import ../../lib/ipc/ipc_request
import ../../lib/ipc/service_client
import ../../lib/core/args
import ../../lib/core/options
import ../../lib/core/syscall

const
  PsMaxEntries = int(SysProcessMaxSlots)

let optionSpecs = [
  OptionSpec(short: 'f', long: cstring(nil)),
  OptionSpec(short: 'e', long: cstring(nil)),
]

var
  entries: array[PsMaxEntries, SysProcessInfo]
  requestPacket: SysIpcPacket
  responsePacket: SysIpcPacket
  parsedArgs: UserArgs
  parsedOptions: ParsedOptions


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


proc printPid(pid: I32) =
  if pid < 0:
    write("-")
    writeUnsigned(U64(-pid))
  else:
    writeUnsigned(U64(pid))


proc printProcess(entry: ptr SysProcessInfo, full: bool) =
  printPid(entry.pid)
  if not full:
    write("\t")
    write(cast[cstring](addr entry.exePath[0]))
    write("\n")
    return

  write("\t")
  printPid(entry.ppid)
  write("\t")
  write(stateName(entry.state))
  write("\t")
  write(modeName(entry.isUser))
  write("\t")
  write(cast[cstring](addr entry.exePath[0]))
  write("\n")


proc sortProcessByPid(entries: var array[PsMaxEntries, SysProcessInfo], count: I32) =
  var i = 1

  while i < count:
    let key = entries[i]
    var j = i
    
    while j > 0 and entries[j - 1].pid > key.pid:
      entries[j] = entries[j - 1]
      dec j
    
    entries[j] = key
    inc i


proc findEntryIndex(pid: I32, count: I32): I32 =
  var i = I32(0)
  while i < count:
    if entries[i].pid == pid:
      return i
    inc i

  -1


proc isDescendantOf(pid, rootPid: I32, count: I32): bool =
  var cur = pid
  var depth = I32(0)

  while cur > 0 and depth < count:
    if cur == rootPid:
      return true

    let idx = findEntryIndex(cur, count)
    if idx < 0:
      return false

    cur = entries[idx].ppid
    inc depth

  false


proc shouldPrintProcess(entry: ptr SysProcessInfo, count: I32, fullList: bool): bool =
  if entry.state == SysProcessUnused:
    return false

  if fullList:
    return true

  let selfPid = sysGetPid()
  let selfIdx = findEntryIndex(selfPid, count)
  if selfIdx < 0:
    return true

  let rootPid = entries[selfIdx].ppid
  if rootPid <= 0:
    return true

  entry.pid == rootPid or isDescendantOf(entry.pid, rootPid, count)


proc printHeader(full: bool) =
  if full:
    write("pid\tppid\tstate\t\tmode\texe\n")
  else:
    write("pid\texe\n")


proc printProcesses(count: I32, full, every: bool) =
  if not every:
    sortProcessByPid(entries, count)

  printHeader(full)
  var i = I32(0)
  while i < count:
    if shouldPrintProcess(addr entries[i], count, every):
      printProcess(addr entries[i], full)
    inc i


proc processManagerPid(): I32 =
  servicePidByKind(SysServiceKindProcess)


proc copyPacketToProcess(entry: ptr SysProcessInfo, packet: ptr SysIpcPacket) =
  discard copyFromPacketData(entry, packet, U32(sizeof(SysProcessInfo)))


proc requestProcessList(maxEntries: I32, flags: U64): I32 =
  let pid = processManagerPid()
  if pid <= 0:
    return -1

  requestPacket = SysIpcPacket()
  requestPacket.op = SysIpcOpProcListRequest
  requestPacket.arg0 = U64(maxEntries)
  requestPacket.arg1 = flags
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
  write("usage: ps [-f] [-e]\n")
  write("  -f    show pid, ppid, state, mode, and exe\n")
  write("  -e    show all process slots\n")


proc user_start*(arg: cstring) {.exportc, cdecl, noreturn.} =
  if not parseUserArgs(arg, parsedArgs):
    printUsage()
    sysExit(1)

  if not parseOptions(parsedArgs, optionSpecs, parsedOptions):
    printUsage()
    sysExit(1)

  if parsedOptions.help:
    printUsage()
    sysExit(0)

  if parsedOptions.positionalCount != 0:
    printUsage()
    sysExit(1)

  let full = hasOption(parsedOptions, 'f')
  let every = hasOption(parsedOptions, 'e')

  let count = requestProcessList(I32(PsMaxEntries), U64(0))
  if count < 0:
    write("ps: failed\n")
    sysExit(1)

  printProcesses(count, full, every)

  sysExit(0)
