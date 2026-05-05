import ../../../lib/syscall_types
import ../../../lib/types
import ../../service/registry
import ../../task/process


proc serviceKindFromValue(value: U64, kind: var ServiceKind): bool =
  if value == U64(SysServiceKindBlock):
    kind = serviceBlock
    return true

  if value == U64(SysServiceKindFs):
    kind = serviceFs
    return true

  if value == U64(SysServiceKindManager):
    kind = serviceManager
    return true

  false


proc servicePidIsUsable(pid: int32): bool =
  let p = findProcessByPid(pid)
  p != nil and p.state != procUnused and p.state != procZombie and p.user.active


proc syscallServiceManagerRegister*(): U64 =
  if currentProc == nil or not currentProc.user.active:
    return U64(-1'i64)

  if serviceRegistered(serviceManager) and not currentIsService(serviceManager):
    return U64(-1'i64)

  registerService(serviceManager, currentProc.pid)
  0


proc syscallServiceRegister*(kindVal, pidVal: U64): U64 =
  if not currentIsService(serviceManager):
    return U64(-1'i64)

  var kind = serviceBlock
  if not serviceKindFromValue(kindVal, kind):
    return U64(-1'i64)
  if kind == serviceManager:
    return U64(-1'i64)

  let pid = int32(pidVal)
  if not servicePidIsUsable(pid):
    return U64(-1'i64)

  registerService(kind, pid)
  0


proc syscallServiceUnregister*(kindVal: U64): U64 =
  if not currentIsService(serviceManager):
    return U64(-1'i64)

  var kind = serviceBlock
  if not serviceKindFromValue(kindVal, kind):
    return U64(-1'i64)
  if kind == serviceManager:
    return U64(-1'i64)

  unregisterService(kind)
  0
