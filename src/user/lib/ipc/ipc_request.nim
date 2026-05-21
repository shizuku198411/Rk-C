## Provides request/reply IPC helpers for userland service clients.
import ../core/syscall


## Sends ipc request.
proc sendIpcRequest*(pid: I32, packet: ptr SysIpcPacket): I32 =
  if pid <= 0 or packet == nil:
    return -1

  sysIpcSendPacket(pid, packet)


## Receives ipc reply.
proc receiveIpcReply*(pid: I32, packet: ptr SysIpcPacket, expectedOp: U32): I32 =
  if pid <= 0 or packet == nil:
    return -1

  if sysIpcReceivePacket(packet) != 0:
    return -1
  if packet.senderPid != pid:
    return -1
  if packet.op != expectedOp:
    return -1

  0


## Requests ipc reply.
proc requestIpcReply*(pid: I32, request, reply: ptr SysIpcPacket, expectedOp: U32): I32 =
  if sendIpcRequest(pid, request) != 0:
    return -1

  receiveIpcReply(pid, reply, expectedOp)
