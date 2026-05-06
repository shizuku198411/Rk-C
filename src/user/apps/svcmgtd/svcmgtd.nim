import ../../lib/io
import ../../lib/syscall

const
  ProcessCap = 16
  MonitorSleepTicks = U64(10)

type
  ServiceState = enum
    srvStopped
    srvRunning

  ServiceEntry = object
    kind: U32
    name: cstring
    path: cstring
    pid: I32
    state: ServiceState
    restarts: U64

var
  services: array[2, ServiceEntry]
  processes: array[ProcessCap, SysProcessInfo]


proc initServices() =
  services[0].kind = SysServiceKindBlock
  services[0].name = "blockd"
  services[0].path = "/bin/blockd"
  services[0].pid = -1
  services[0].state = srvStopped

  services[1].kind = SysServiceKindFs
  services[1].name = "fsd"
  services[1].path = "/bin/fsd"
  services[1].pid = -1
  services[1].state = srvStopped


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


proc reapService(entry: ptr ServiceEntry) =
  if entry.pid <= 0:
    return

  var state = U32(0)
  if processState(entry.pid, state) and state == SysProcessZombie:
    discard sysWait(entry.pid)

  entry.pid = -1


proc startService(entry: ptr ServiceEntry) =
  let pid = sysExec(entry.path, nil, false)
  if pid < 0:
    write("[svcmgtd] failed to start ")
    write(entry.name)
    write("\n")
    entry.state = srvStopped
    return

  if sysServiceRegister(entry.kind, pid) != 0:
    write("[svcmgtd] failed to register ")
    write(entry.name)
    write("\n")
    discard sysKill(pid)
    discard sysWait(pid)
    entry.state = srvStopped
    entry.pid = -1
    return

  entry.pid = pid
  entry.state = srvRunning
  write("[svcmgtd] service started ")
  write(entry.name)
  write(" pid=")
  writeUnsigned(U64(pid))
  write("\n")


proc restartService(entry: ptr ServiceEntry) =
  unregisterService(entry)
  reapService(entry)
  inc entry.restarts
  startService(entry)


proc monitorServices() =
  var i = 0
  while i < len(services):
    if not serviceAlive(addr services[i]):
      write("[svcmgtd] service restarting ")
      write(services[i].name)
      write("\n")
      restartService(addr services[i])
    inc i


proc user_start*(arg: cstring) {.exportc, cdecl, noreturn.} =
  discard arg

  var pid = sysGetPid()
  write("[svcmgtd] service management server started pid=")
  writeUnsigned(U64(pid))
  write("\n")

  if sysServiceManagerRegister() != 0:
    write("[svcmgtd] service register failed\n")
    sysExit(1)

  initServices()
  startService(addr services[0])
  startService(addr services[1])

  while true:
    monitorServices()
    discard sysSleep(MonitorSleepTicks)
