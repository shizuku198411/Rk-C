import ../../lib/core/syscall
import ../../lib/ipc/service_client


proc notifyServiceReady*(kind: U32) =
  let managerPid = servicePidByKind(SysServiceKindManager)
  if managerPid <= 0:
    return

  var packet = SysIpcPacket()
  packet.op = SysIpcOpSvcReady
  packet.arg0 = U64(kind)
  discard sysIpcSendPacket(managerPid, addr packet)
