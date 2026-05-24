## Owns the process snapshot workspace and procmgtd request exchange for ps.

var
  requestPacket: SysIpcPacket
  responsePacket: SysIpcPacket


## Allocates the stable ORC-managed process snapshot workspace.
proc initManagedStorage(): bool =
  entries = newSeq[SysProcessInfo](PsMaxEntries)
  entries.len == PsMaxEntries


## Returns the process manager service pid.
proc processManagerPid(): I32 =
  servicePidByKind(SysServiceKindProcess)


## Copies packed process info from an IPC packet into a process entry.
proc copyPacketToProcess(entry: ptr SysProcessInfo, packet: ptr SysIpcPacket) =
  discard copyFromPacketData(entry, packet, U32(sizeof(SysProcessInfo)))


## Requests a process list from procmgtd into the managed snapshot workspace.
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
