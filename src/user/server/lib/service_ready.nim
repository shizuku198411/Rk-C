import ../../lib/core/syscall
import ../../lib/ipc/service_client

const
  ServiceRegistrationWaitTicks = U64(1)
  ServiceRegistrationTimeoutTicks = U64(200)


proc waitUntilServiceRegistered*(kind: U32): bool =
  let selfPid = sysGetPid()
  let start = sysTicks()

  while sysTicks() - start < ServiceRegistrationTimeoutTicks:
    if registeredServicePidByKind(kind) == selfPid:
      return true
    discard sysSleep(ServiceRegistrationWaitTicks)

  false


proc notifyServiceReady*(kind: U32) =
  let managerPid = servicePidByKind(SysServiceKindManager)
  if managerPid <= 0:
    return

  var packet = SysIpcPacket()
  packet.op = SysIpcOpSvcReady
  packet.arg0 = U64(kind)
  discard sysIpcSendPacket(managerPid, addr packet)
