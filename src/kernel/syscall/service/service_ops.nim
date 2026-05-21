## Implements service registry syscall handlers.
import ../../../lib/fixed_string
import ../../../lib/service_catalog
import ../../../lib/syscall_types
import ../../../lib/types
import ../../lib/syscall_out
import ../../service/registry
import ../../task/process
import ../syscall_cap


var serviceInfos: array[serviceMax, SysServiceInfo]


## Implements the service kind from value kernel helper.
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

  if value == U64(SysServiceKindProcess):
    kind = serviceProcess
    return true

  if value == U64(SysServiceKindNet):
    kind = serviceNet
    return true

  if value == U64(SysServiceKindProcFs):
    kind = serviceProcFs
    return true

  if value == U64(SysServiceKindUser):
    kind = serviceUser
    return true

  false


## Implements the service pid is usable kernel helper.
proc servicePidIsUsable(pid: int32): bool =
  let p = findProcessByPid(pid)
  p != nil and p.state != procUnused and p.state != procZombie and p.user.active


## Implements the service kind value kernel helper.
proc serviceKindValue(kind: ServiceKind): U32 =
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
  of serviceProcFs:
    SysServiceKindProcFs
  of serviceUser:
    SysServiceKindUser
  of serviceMax:
    U32(0xffffffff'u32)


## Fills service info.
proc fillServiceInfo(kind: ServiceKind) =
  serviceInfos[kind] = SysServiceInfo()
  serviceInfos[kind].kind = serviceKindValue(kind)
  serviceInfos[kind].pid = servicePid(kind)
  if serviceRegistered(kind):
    serviceInfos[kind].registered = 1
  else:
    serviceInfos[kind].registered = 0
  if serviceAvailable(kind):
    serviceInfos[kind].available = 1
  else:
    serviceInfos[kind].available = 0
  discard copyCString(serviceInfos[kind].name, serviceNameByKind(serviceKindValue(kind)))


## Handles the service manager register syscall operation.
proc syscallServiceManagerRegister*(): U64 =
  if not canSyscallServiceManagerRegister():
    return U64(-1'i64)

  registerService(serviceManager, currentProc.pid, true)
  0


## Handles the service register syscall operation.
proc syscallServiceRegister*(kindVal, pidVal: U64): U64 =
  var kind = serviceBlock
  if not serviceKindFromValue(kindVal, kind):
    return U64(-1'i64)
  if not canSyscallServiceKindMutation(kind):
    return U64(-1'i64)

  let pid = int32(pidVal)
  if not servicePidIsUsable(pid):
    return U64(-1'i64)

  registerService(kind, pid)
  0


## Handles the service ready syscall operation.
proc syscallServiceReady*(kindVal, pidVal: U64): U64 =
  var kind = serviceBlock
  if not serviceKindFromValue(kindVal, kind):
    return U64(-1'i64)
  if not canSyscallServiceKindMutation(kind):
    return U64(-1'i64)

  if not markServiceReady(kind, int32(pidVal)):
    return U64(-1'i64)

  0


## Handles the service unregister syscall operation.
proc syscallServiceUnregister*(kindVal: U64): U64 =
  var kind = serviceBlock
  if not serviceKindFromValue(kindVal, kind):
    return U64(-1'i64)
  if not canSyscallServiceKindMutation(kind):
    return U64(-1'i64)

  unregisterService(kind)
  0


## Handles the service list syscall operation.
proc syscallServiceList*(outEntries, maxEntries: U64): U64 =
  if outEntries == 0 or maxEntries == 0:
    return U64(-1'i64)

  var count = U64(0)
  var kind = low(ServiceKind)
  while kind < serviceMax and count < maxEntries:
    fillServiceInfo(kind)
    inc count
    kind = ServiceKind(ord(kind) + 1)

  let bytes = count * U64(sizeof(SysServiceInfo))
  if not copyOutBuffer(outEntries, addr serviceInfos[serviceManager], bytes):
    return U64(-1'i64)

  count
