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


## Includes formats service-manager state and initializes service descriptors.
include ./internal/formatting


## Includes tracks service health and controls process start, stop, and restart.
include ./internal/lifecycle


## Includes handles service-manager ipc status and lifecycle control requests.
include ./internal/control


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
