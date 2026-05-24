## Handles service-manager IPC status and lifecycle control requests.

proc findServiceByName(name: cstring): ptr ServiceEntry =
  var i = 0
  while i < len(services):
    if cstringEq(services[i].name, name):
      return addr services[i]
    inc i

  nil


proc copyNameFromPacket(packet: ptr SysIpcPacket): cstring =
  cast[cstring](addr packet.data[0])


proc replyText(toPid: I32, op: U32, ok: bool, text: cstring) =
  replyPacket = SysIpcPacket()
  replyPacket.op = op
  if ok:
    replyPacket.arg0 = U64(0)
  else:
    replyPacket.arg0 = U64(-1'i64)
  clearPacketData(replyPacket)

  var pos = U32(0)
  appendStr(cast[ptr UncheckedArray[char]](addr replyPacket.data[0]), SysIpcMessageMax, pos, text)
  replyPacket.len = pos
  discard sysIpcSendPacket(toPid, addr replyPacket)


proc beginReply(toPid: I32, op: U32) =
  replyPacket = SysIpcPacket()
  replyPacket.op = op
  replyPacket.arg0 = U64(0)
  clearPacketData(replyPacket)


proc finishReply(toPid: I32, ok: bool, pos: U32) =
  if ok:
    replyPacket.arg0 = U64(0)
  else:
    replyPacket.arg0 = U64(-1'i64)
  replyPacket.len = pos
  discard sysIpcSendPacket(toPid, addr replyPacket)


proc appendServiceStatus(pos: var U32, entry: ptr ServiceEntry) =
  let buf = cast[ptr UncheckedArray[char]](addr replyPacket.data[0])
  appendStr(buf, SysIpcMessageMax, pos, entry.name)
  appendChar(buf, SysIpcMessageMax, pos, '\t')
  appendStr(buf, SysIpcMessageMax, pos, stateName(entry.state))
  appendChar(buf, SysIpcMessageMax, pos, '\t')
  appendI32(buf, SysIpcMessageMax, pos, entry.pid)
  appendChar(buf, SysIpcMessageMax, pos, '\t')
  appendU64(buf, SysIpcMessageMax, pos, entry.startCount)
  appendChar(buf, SysIpcMessageMax, pos, '\t')
  appendU64(buf, SysIpcMessageMax, pos, entry.restarts)
  appendChar(buf, SysIpcMessageMax, pos, '\t')
  appendU64(buf, SysIpcMessageMax, pos, entry.lastReadyTick)
  appendChar(buf, SysIpcMessageMax, pos, '\t')
  appendStr(buf, SysIpcMessageMax, pos, entry.lastFailureReason)
  appendChar(buf, SysIpcMessageMax, pos, '\n')


proc handleStatusRequest(packet: ptr SysIpcPacket) =
  let filterName = copyNameFromPacket(packet)
  let degradedOnly = packet.arg0 != U64(0)
  beginReply(packet.senderPid, SysIpcOpSvcStatusResponse)

  var pos = U32(0)
  let buf = cast[ptr UncheckedArray[char]](addr replyPacket.data[0])
  appendStr(buf, SysIpcMessageMax, pos, cstring("service\tstate\tpid\tstarts\trestarts\tready_tick\treason\n"))

  var found = false
  var i = 0
  while i < len(services):
    let nameMatches = filterName[0] == '\0' or cstringEq(services[i].name, filterName)
    let degradedMatches = not degradedOnly or services[i].state == srvDegraded
    if nameMatches and degradedMatches:
      appendServiceStatus(pos, addr services[i])
      found = true
    inc i

  if not found:
    appendStr(buf, SysIpcMessageMax, pos, cstring("none\n"))

  finishReply(packet.senderPid, true, pos)


proc handleLogsRequest(packet: ptr SysIpcPacket) =
  beginReply(packet.senderPid, SysIpcOpSvcLogsResponse)
  var pos = U32(0)
  let buf = cast[ptr UncheckedArray[char]](addr replyPacket.data[0])

  if serviceLogTotal == U32(0):
    appendStr(buf, SysIpcMessageMax, pos, cstring("no service events\n"))
  else:
    var emitted = U32(0)
    var idx =
      if serviceLogTotal < U32(ServiceLogCount):
        U32(0)
      else:
        serviceLogNext

    while emitted < serviceLogTotal:
      appendStr(buf, SysIpcMessageMax, pos, cast[cstring](addr serviceLogs[idx][0]))
      appendChar(buf, SysIpcMessageMax, pos, '\n')
      idx = (idx + U32(1)) mod U32(ServiceLogCount)
      inc emitted

  finishReply(packet.senderPid, true, pos)


proc handleStartCommand(packet: ptr SysIpcPacket) =
  let service = findServiceByName(copyNameFromPacket(packet))
  if service == nil:
    replyText(packet.senderPid, SysIpcOpSvcCommandResponse, false, cstring("unknown service\n"))
    return
  if service.state == srvStarting or service.state == srvRunning:
    replyText(packet.senderPid, SysIpcOpSvcCommandResponse, false, cstring("service already active\n"))
    return

  startService(service)
  replyText(packet.senderPid, SysIpcOpSvcCommandResponse, true, cstring("service start requested\n"))


proc handleStopCommand(packet: ptr SysIpcPacket) =
  let service = findServiceByName(copyNameFromPacket(packet))
  if service == nil:
    replyText(packet.senderPid, SysIpcOpSvcCommandResponse, false, cstring("unknown service\n"))
    return
  if service.required:
    replyText(packet.senderPid, SysIpcOpSvcCommandResponse, false, cstring("cannot stop required service\n"))
    return
  if service.state == srvStopped or service.state == srvDegraded:
    replyText(packet.senderPid, SysIpcOpSvcCommandResponse, false, cstring("service not running\n"))
    return

  stopService(service, cstring("manual_stop"))
  service.state = srvDegraded
  service.lastFailureReason = cstring("manual_stop")
  replyText(packet.senderPid, SysIpcOpSvcCommandResponse, true, cstring("service stopped\n"))


proc handleRestartRequest(packet: ptr SysIpcPacket) =
  let service = findServiceByName(copyNameFromPacket(packet))
  if service == nil:
    replyText(packet.senderPid, SysIpcOpSvcCommandResponse, false, cstring("unknown service\n"))
    return

  restartService(service)
  replyText(packet.senderPid, SysIpcOpSvcCommandResponse, true, cstring("service restart requested\n"))


proc handleReadyPacket(packet: ptr SysIpcPacket) =
  let service = findServiceByPid(packet.senderPid)
  if service == nil:
    write("[svcmgtd] ready from unknown pid=")
    writeUnsigned(U64(packet.senderPid))
    write("\n")
    return

  if service.state != srvStarting:
    return

  if packet.arg0 != U64(service.kind):
    write("[svcmgtd] ready kind mismatch pid=")
    writeUnsigned(U64(packet.senderPid))
    write("\n")
    return

  markServiceReady(service)


proc handleControlPacket(packet: ptr SysIpcPacket) =
  if packet.op == SysIpcOpSvcRestart:
    if packet.uid != RootUid or (packet.capabilityMask and SysCapServiceManager) == 0:
      return
    handleRestartRequest(packet)
  elif packet.op == SysIpcOpSvcStart:
    if packet.uid != RootUid or (packet.capabilityMask and SysCapServiceManager) == 0:
      return
    handleStartCommand(packet)
  elif packet.op == SysIpcOpSvcStop:
    if packet.uid != RootUid or (packet.capabilityMask and SysCapServiceManager) == 0:
      return
    handleStopCommand(packet)
  elif packet.op == SysIpcOpSvcStatusRequest:
    if packet.uid != RootUid or (packet.capabilityMask and SysCapServiceManager) == 0:
      return
    handleStatusRequest(packet)
  elif packet.op == SysIpcOpSvcLogsRequest:
    if packet.uid != RootUid or (packet.capabilityMask and SysCapServiceManager) == 0:
      return
    handleLogsRequest(packet)
  elif packet.op == SysIpcOpSvcReady:
    handleReadyPacket(packet)


