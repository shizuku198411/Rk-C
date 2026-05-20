import ../../lib/core/io
import ../../lib/core/strutils
import ../../lib/core/syscall
import ../../../lib/service_catalog
import ../../../lib/syscall_caps
import ../../../lib/user_ids

const
  ProcessCap = int(SysProcessMaxSlots)
  MonitorSleepTicks = U64(10)
  ServiceReadyTimeoutTicks = U64(200)
  ServiceLogCount = 8
  ServiceLogLen = 96
  ServiceLivenessMissLimit = U32(3)

type
  ServiceState = enum
    srvStopped
    srvDegraded
    srvStarting
    srvRunning

  ServiceEntry = object
    kind: U32
    name: cstring
    path: cstring
    required: bool
    pid: I32
    state: ServiceState
    startCount: U64
    restarts: U64
    readyDeadline: U64
    lastReadyTick: U64
    lastExitStatus: U64
    lastFailureReason: cstring
    livenessMisses: U32

var
  services: array[SysManagedServiceCount, ServiceEntry]
  processes: array[ProcessCap, SysProcessInfo]
  kernelServices: array[8, SysServiceInfo]
  controlPacket: SysIpcPacket
  replyPacket: SysIpcPacket
  pendingSignal: U32
  serviceLogs: array[ServiceLogCount, array[ServiceLogLen, char]]
  serviceLogNext: U32
  serviceLogTotal: U32


proc stateName(state: ServiceState): cstring =
  case state
  of srvStopped: cstring("stopped")
  of srvDegraded: cstring("degraded")
  of srvStarting: cstring("starting")
  of srvRunning: cstring("running")


proc appendChar(buf: ptr UncheckedArray[char], cap: U32, pos: var U32, ch: char) =
  if pos + U32(1) < cap:
    buf[pos] = ch
    inc pos
    buf[pos] = '\0'


proc appendStr(buf: ptr UncheckedArray[char], cap: U32, pos: var U32, s: cstring) =
  var i = U32(0)
  while s[i] != '\0':
    appendChar(buf, cap, pos, s[i])
    inc i


proc appendU64(buf: ptr UncheckedArray[char], cap: U32, pos: var U32, value: U64) =
  var
    tmp: array[32, char]
    n = value
    i = U32(0)

  if n == U64(0):
    appendChar(buf, cap, pos, '0')
    return

  while n > U64(0) and i < U32(32):
    tmp[i] = char(ord('0') + int(n mod U64(10)))
    n = n div U64(10)
    inc i

  while i > U32(0):
    dec i
    appendChar(buf, cap, pos, tmp[i])


proc appendI32(buf: ptr UncheckedArray[char], cap: U32, pos: var U32, value: I32) =
  if value < 0:
    appendChar(buf, cap, pos, '-')
    appendU64(buf, cap, pos, U64(-value))
  else:
    appendU64(buf, cap, pos, U64(value))


proc clearPacketData(packet: var SysIpcPacket) =
  var i = U32(0)
  while i < SysIpcMessageMax:
    packet.data[i] = '\0'
    inc i


proc logEvent(name, action: cstring) =
  let idx = serviceLogNext mod U32(ServiceLogCount)
  var pos = U32(0)
  let line = cast[ptr UncheckedArray[char]](addr serviceLogs[idx][0])

  var i = U32(0)
  while i < U32(ServiceLogLen):
    line[i] = '\0'
    inc i

  appendStr(line, U32(ServiceLogLen), pos, cstring("["))
  appendU64(line, U32(ServiceLogLen), pos, sysTicks())
  appendStr(line, U32(ServiceLogLen), pos, cstring("] "))
  appendStr(line, U32(ServiceLogLen), pos, name)
  appendStr(line, U32(ServiceLogLen), pos, cstring(" "))
  appendStr(line, U32(ServiceLogLen), pos, action)

  serviceLogNext = (serviceLogNext + U32(1)) mod U32(ServiceLogCount)
  if serviceLogTotal < U32(ServiceLogCount):
    inc serviceLogTotal


proc initServices() =
  var i = 0
  while i < len(services):
    services[i].kind = managedServices[i].kind
    services[i].name = managedServices[i].name
    services[i].path = managedServices[i].path
    services[i].required = managedServices[i].required
    services[i].pid = -1
    services[i].state = srvStopped
    services[i].startCount = 0
    services[i].restarts = 0
    services[i].readyDeadline = 0
    services[i].lastReadyTick = 0
    services[i].lastExitStatus = 0
    services[i].lastFailureReason = cstring("none")
    services[i].livenessMisses = U32(0)
    inc i


proc processState(pid: I32, state: var U32): bool =
  let count = sysPs(addr processes[0], U64(ProcessCap), SysProcListAllSlots)
  if count < 0:
    return false

  var i = I32(0)
  while i < count:
    if processes[i].pid == pid:
      state = processes[i].state
      return true
    inc i

  false


proc serviceAlive(entry: ptr ServiceEntry): bool =
  if entry.pid <= 0:
    return false

  if entry.state == srvRunning:
    let count = sysServiceList(addr kernelServices[0], U64(8))
    if count < 0:
      return false

    var i = I32(0)
    while i < count:
      if kernelServices[i].kind == entry.kind and kernelServices[i].pid == entry.pid:
        return kernelServices[i].available != U32(0)
      inc i

    return false

  var state = U32(0)
  if not processState(entry.pid, state):
    return false

  state != SysProcessZombie and state != SysProcessUnused


proc unregisterService(entry: ptr ServiceEntry) =
  discard sysServiceUnregister(entry.kind)
  entry.state = srvStopped


proc stopService(entry: ptr ServiceEntry, reason: cstring = cstring("manual_stop")) =
  unregisterService(entry)
  if entry.pid <= 0:
    entry.lastFailureReason = reason
    return

  if serviceAlive(entry):
    discard sysKill(entry.pid)

  entry.lastExitStatus = sysWait(entry.pid)
  entry.pid = -1
  entry.state = srvStopped
  entry.lastFailureReason = reason
  logEvent(entry.name, reason)


proc degradeService(entry: ptr ServiceEntry, reason: cstring = cstring("degraded")) =
  unregisterService(entry)
  if entry.pid > 0:
    if serviceAlive(entry):
      discard sysKill(entry.pid)
    entry.lastExitStatus = sysWait(entry.pid)
  entry.pid = -1
  entry.state = srvDegraded
  entry.lastFailureReason = reason
  logEvent(entry.name, reason)
  write("[svcmgtd] service degraded ")
  write(entry.name)
  write("\n")


proc findServiceByPid(pid: I32): ptr ServiceEntry =
  var i = 0
  while i < len(services):
    if services[i].pid == pid:
      return addr services[i]
    inc i

  nil


proc markServiceReady(entry: ptr ServiceEntry) =
  if entry == nil or entry.pid <= 0:
    return

  if sysServiceReady(entry.kind, entry.pid) != 0:
    write("[svcmgtd] failed to mark ready ")
    write(entry.name)
    write("\n")
    return

  entry.state = srvRunning
  entry.lastReadyTick = sysTicks()
  entry.lastFailureReason = cstring("none")
  entry.livenessMisses = U32(0)
  logEvent(entry.name, cstring("ready"))
  write("[svcmgtd] service ready ")
  write(entry.name)
  write(" pid=")
  writeUnsigned(U64(entry.pid))
  write("\n")


proc startService(entry: ptr ServiceEntry) =
  inc entry.startCount
  let pid = sysExec(entry.path, nil, false)
  if pid < 0:
    write("[svcmgtd] failed to start ")
    write(entry.name)
    write("\n")
    if entry.required:
      entry.state = srvStopped
      entry.lastFailureReason = cstring("start_failed")
      logEvent(entry.name, cstring("start_failed"))
    else:
      degradeService(entry, cstring("start_failed"))
    return

  if sysServiceRegister(entry.kind, pid) != 0:
    write("[svcmgtd] failed to register ")
    write(entry.name)
    write("\n")
    discard sysKill(pid)
    discard sysWait(pid)
    entry.pid = -1
    if entry.required:
      entry.state = srvStopped
      entry.lastFailureReason = cstring("register_failed")
      logEvent(entry.name, cstring("register_failed"))
    else:
      degradeService(entry, cstring("register_failed"))
    return

  entry.pid = pid
  entry.state = srvStarting
  entry.readyDeadline = sysTicks() + ServiceReadyTimeoutTicks
  entry.lastFailureReason = cstring("none")
  entry.livenessMisses = U32(0)
  logEvent(entry.name, cstring("started"))
  write("[svcmgtd] service started ")
  write(entry.name)
  write(" pid=")
  writeUnsigned(U64(pid))
  write("\n")


proc restartService(entry: ptr ServiceEntry) =
  stopService(entry, cstring("restart_requested"))
  inc entry.restarts
  startService(entry)


proc handleServiceProcessExit(entry: ptr ServiceEntry, reason: cstring) =
  if entry.pid > 0:
    entry.lastExitStatus = sysWait(entry.pid)
  entry.pid = -1
  entry.livenessMisses = U32(0)

  if entry.required:
    write("[svcmgtd] service restarting ")
    write(entry.name)
    write("\n")
    entry.state = srvStopped
    entry.lastFailureReason = reason
    logEvent(entry.name, reason)
    inc entry.restarts
    startService(entry)
  else:
    discard sysServiceUnregister(entry.kind)
    entry.state = srvDegraded
    entry.lastFailureReason = reason
    logEvent(entry.name, reason)
    write("[svcmgtd] service degraded ")
    write(entry.name)
    write("\n")


proc handleExitedServiceSignals() =
  while sysSignalPoll(addr pendingSignal) == 0 and pendingSignal != SysSignalNone:
    if pendingSignal == SysSignalChildExited:
      var i = 0
      while i < len(services):
        if services[i].pid > 0 and not serviceAlive(addr services[i]):
          handleServiceProcessExit(addr services[i], cstring("process_exit"))
        inc i


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


proc pollControlMessages() =
  while sysIpcTryReceivePacket(addr controlPacket) == 0:
    handleControlPacket(addr controlPacket)


proc monitorServices() =
  handleExitedServiceSignals()

  var i = 0
  while i < len(services):
    if services[i].state == srvDegraded and not services[i].required:
      inc i
      continue

    if services[i].state == srvStarting and sysTicks() >= services[i].readyDeadline:
      write("[svcmgtd] service ready timeout ")
      write(services[i].name)
      write("\n")
      if services[i].required:
        restartService(addr services[i])
      else:
        degradeService(addr services[i], cstring("ready_timeout"))
      inc i
      continue

    if serviceAlive(addr services[i]):
      services[i].livenessMisses = U32(0)
      inc i
      continue

    inc services[i].livenessMisses
    if services[i].livenessMisses < ServiceLivenessMissLimit:
      inc i
      continue

    services[i].livenessMisses = U32(0)
    handleServiceProcessExit(addr services[i], cstring("process_exit"))
    inc i


proc waitForServiceReady(entry: ptr ServiceEntry) =
  while entry.state == srvStarting and sysTicks() < entry.readyDeadline:
    handleExitedServiceSignals()
    pollControlMessages()
    discard sysSleep(1)

  if entry.state == srvStarting:
    write("[svcmgtd] service ready timeout ")
    write(entry.name)
    write("\n")
    if entry.required:
      stopService(entry, cstring("ready_timeout"))
    else:
      degradeService(entry, cstring("ready_timeout"))


proc startInitialService(entry: ptr ServiceEntry) =
  startService(entry)
  waitForServiceReady(entry)


proc user_start*(arg: cstring) {.exportc, cdecl, noreturn.} =
  discard arg

  let pid = sysGetPid()
  write("[svcmgtd] service management server started pid=")
  writeUnsigned(U64(pid))
  write("\n")

  if sysServiceManagerRegister() != 0:
    write("[svcmgtd] service register failed\n")
    sysExit(1)

  initServices()
  var i = 0
  while i < len(services):
    startInitialService(addr services[i])
    inc i

  while true:
    pollControlMessages()
    monitorServices()
    discard sysSleep(MonitorSleepTicks)
