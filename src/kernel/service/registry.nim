import ../../lib/service_catalog
import ../../lib/syscall_types
import ../../lib/types
import ../task/process

type
  ServiceKind* = enum
    serviceManager = 0
    serviceBlock
    serviceFs
    serviceProcess
    serviceNet
    serviceMax

  ServiceEntry = object
    registered: bool
    ready: bool
    pid: int32

var services: array[serviceMax, ServiceEntry]


proc registerService*(kind: ServiceKind, pid: int32, ready: bool = false) =
  services[kind].registered = true
  services[kind].ready = ready
  services[kind].pid = pid


proc unregisterService*(kind: ServiceKind) =
  services[kind].registered = false
  services[kind].ready = false
  services[kind].pid = 0


proc serviceRegistered*(kind: ServiceKind): bool =
  services[kind].registered


proc servicePid*(kind: ServiceKind): int32 =
  services[kind].pid


proc serviceReady*(kind: ServiceKind): bool =
  services[kind].ready


proc markServiceReady*(kind: ServiceKind, pid: int32): bool =
  if not services[kind].registered or services[kind].pid != pid:
    return false

  let p = findProcessByPid(pid)
  if p == nil or p.state == procZombie or p.state == procUnused:
    return false

  services[kind].ready = true
  true


proc currentIsService*(kind: ServiceKind): bool =
  currentProc != nil and services[kind].registered and currentProc.pid == services[kind].pid


proc serviceAvailable*(kind: ServiceKind): bool =
  if not services[kind].registered or not services[kind].ready:
    return false

  let p = findProcessByPid(services[kind].pid)
  p != nil and p.state != procZombie and p.state != procUnused


proc isServicePid*(pid: int32): bool =
  var kind = low(ServiceKind)

  while kind < serviceMax:
    if services[kind].registered and services[kind].pid == pid:
      return true
    kind = ServiceKind(ord(kind) + 1)

  false


proc sysServiceKindValue(kind: ServiceKind): U32 =
  case kind
  of serviceManager:
    SysServiceKindManager
  of serviceBlock:
    SysServiceKindBlock
  of serviceFs:
    SysServiceKindFs
  of serviceProcess:
    SysServiceKindProcess
  of serviceNet:
    SysServiceKindNet
  of serviceMax:
    U32(0xffffffff'u32)


proc serviceRequired*(kind: ServiceKind): bool =
  serviceRequiredByKind(sysServiceKindValue(kind))


proc requiredServicesReady*(): bool =
  var kind = low(ServiceKind)

  while kind < serviceMax:
    if serviceRequired(kind) and not serviceAvailable(kind):
      return false
    kind = ServiceKind(ord(kind) + 1)
  
  true


proc allServicesReady*(): bool =
  var kind = low(ServiceKind)

  while kind < serviceMax:
    if not serviceAvailable(kind):
      return false
    kind = ServiceKind(ord(kind) + 1)

  true
