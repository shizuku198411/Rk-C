import ../task/process

type
  ServiceKind* = enum
    serviceBlock = 0
    serviceFs
    serviceManager
    serviceMax

  ServiceEntry = object
    registered: bool
    pid: int32

var services: array[serviceMax, ServiceEntry]


proc registerService*(kind: ServiceKind, pid: int32) =
  services[kind].registered = true
  services[kind].pid = pid


proc unregisterService*(kind: ServiceKind) =
  services[kind].registered = false
  services[kind].pid = 0


proc serviceRegistered*(kind: ServiceKind): bool =
  services[kind].registered


proc servicePid*(kind: ServiceKind): int32 =
  services[kind].pid


proc currentIsService*(kind: ServiceKind): bool =
  currentProc != nil and services[kind].registered and currentProc.pid == services[kind].pid


proc serviceAvailable*(kind: ServiceKind): bool =
  if not services[kind].registered:
    return false

  let p = findProcessByPid(services[kind].pid)
  p != nil and p.state != procZombie and p.state != procUnused


proc isServicePid*(pid: int32): bool =
  var kind = serviceBlock
  while kind < serviceMax:
    if services[kind].registered and services[kind].pid == pid:
      return true
    kind = succ(kind)

  false
