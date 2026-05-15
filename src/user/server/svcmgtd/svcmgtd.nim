import ../../lib/core/io
import ../../lib/core/strutils
import ../../lib/core/syscall
import ../../../lib/service_catalog

const
  ProcessCap = 16
  MonitorSleepTicks = U64(10)
  ServiceReadyTimeoutTicks = U64(200)

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
    restarts: U64
    readyDeadline: U64

var
  services: array[SysManagedServiceCount, ServiceEntry]
  processes: array[ProcessCap, SysProcessInfo]
  controlPacket: SysIpcPacket


proc initServices() =
  var i = 0
  while i < len(services):
    services[i].kind = managedServices[i].kind
    services[i].name = managedServices[i].name
    services[i].path = managedServices[i].path
    services[i].required = managedServices[i].required
    services[i].pid = -1
    services[i].state = srvStopped
    services[i].restarts = 0
    services[i].readyDeadline = 0
    inc i


proc processState(pid: I32, state: var U32): bool =
  let count = sysPs(addr processes[0], U64(ProcessCap))
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

  var state = U32(0)
  if not processState(entry.pid, state):
    return false

  state != SysProcessZombie and state != SysProcessUnused


proc unregisterService(entry: ptr ServiceEntry) =
  discard sysServiceUnregister(entry.kind)
  entry.state = srvStopped


proc stopService(entry: ptr ServiceEntry) =
  unregisterService(entry)
  if entry.pid <= 0:
    return

  if serviceAlive(entry):
    discard sysKill(entry.pid)

  discard sysWait(entry.pid)
  entry.pid = -1
  entry.state = srvStopped


proc degradeService(entry: ptr ServiceEntry) =
  unregisterService(entry)
  if entry.pid > 0:
    if serviceAlive(entry):
      discard sysKill(entry.pid)
    discard sysWait(entry.pid)
  entry.pid = -1
  entry.state = srvDegraded
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
  write("[svcmgtd] service ready ")
  write(entry.name)
  write(" pid=")
  writeUnsigned(U64(entry.pid))
  write("\n")


proc startService(entry: ptr ServiceEntry) =
  let pid = sysExec(entry.path, nil, false)
  if pid < 0:
    write("[svcmgtd] failed to start ")
    write(entry.name)
    write("\n")
    if entry.required:
      entry.state = srvStopped
    else:
      degradeService(entry)
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
    else:
      degradeService(entry)
    return

  entry.pid = pid
  entry.state = srvStarting
  entry.readyDeadline = sysTicks() + ServiceReadyTimeoutTicks
  write("[svcmgtd] service started ")
  write(entry.name)
  write(" pid=")
  writeUnsigned(U64(pid))
  write("\n")


proc restartService(entry: ptr ServiceEntry) =
  stopService(entry)
  inc entry.restarts
  startService(entry)


proc findServiceByName(name: cstring): ptr ServiceEntry =
  var i = 0
  while i < len(services):
    if streq(services[i].name, name):
      return addr services[i]
    inc i

  nil


proc handleRestartCommand(name: cstring) =
  if name == nil or name[0] == '\0':
    return

  let service = findServiceByName(name)
  if service == nil:
    write("[svcmgtd] unknown service ")
    write(name)
    write("\n")
    return

  write("[svcmgtd] requested restart ")
  write(service.name)
  write("\n")
  restartService(service)


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
    handleRestartCommand(cast[cstring](addr packet.data[0]))
  elif packet.op == SysIpcOpSvcReady:
    handleReadyPacket(packet)


proc pollControlMessages() =
  while sysIpcTryReceivePacket(addr controlPacket) == 0:
    handleControlPacket(addr controlPacket)


proc monitorServices() =
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
        degradeService(addr services[i])
      inc i
      continue

    if not serviceAlive(addr services[i]):
      if not services[i].required:
        degradeService(addr services[i])
        inc i
        continue

      write("[svcmgtd] service restarting ")
      write(services[i].name)
      write("\n")
      restartService(addr services[i])
    inc i


proc waitForServiceReady(entry: ptr ServiceEntry) =
  while entry.state == srvStarting and sysTicks() < entry.readyDeadline:
    pollControlMessages()
    discard sysSleep(1)

  if entry.state == srvStarting:
    write("[svcmgtd] service ready timeout ")
    write(entry.name)
    write("\n")
    if entry.required:
      stopService(entry)
    else:
      degradeService(entry)


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
  startInitialService(addr services[0])
  startInitialService(addr services[1])
  startInitialService(addr services[2])
  startInitialService(addr services[3])

  while true:
    pollControlMessages()
    monitorServices()
    discard sysSleep(MonitorSleepTicks)
