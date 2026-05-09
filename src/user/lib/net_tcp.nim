import ipc_request
import service_client
import syscall


proc packPorts(srcPort, dstPort: U16): U64 =
  (U64(srcPort) shl 16) or U64(dstPort)


proc tcpConnect*(dstIp: U32, srcPort, dstPort: U16): I32 =
  let pid = servicePidByKind(SysServiceKindNet)
  if pid <= 0:
    return -1

  var request = SysIpcPacket()
  var reply = SysIpcPacket()
  request.op = SysIpcOpNetTcpConnectRequest
  request.arg0 = U64(dstIp)
  request.arg1 = packPorts(srcPort, dstPort)

  if requestIpcReply(pid, addr request, addr reply, SysIpcOpNetTcpConnectResponse) != 0:
    return -1
  if reply.arg0 == U64(-1'i64):
    return -1

  I32(reply.arg0)


proc tcpSend*(handle: I32, data: pointer, len: U32): I32 =
  if handle <= 0 or data == nil or len > SysIpcMessageMax:
    return -1

  let pid = servicePidByKind(SysServiceKindNet)
  if pid <= 0:
    return -1

  var request = SysIpcPacket()
  var reply = SysIpcPacket()
  request.op = SysIpcOpNetTcpSendRequest
  request.arg0 = U64(handle)
  request.len = len

  let src = cast[ptr UncheckedArray[U8]](data)
  var i = 0
  while i < int(len):
    request.data[i] = char(src[i])
    inc i

  if requestIpcReply(pid, addr request, addr reply, SysIpcOpNetTcpSendResponse) != 0:
    return -1
  if reply.arg0 == U64(-1'i64):
    return -1

  I32(reply.arg0)


proc tcpReceive*(handle: I32, data: pointer, capacity: U32): I32 =
  if handle <= 0 or data == nil or capacity == 0:
    return -1

  let pid = servicePidByKind(SysServiceKindNet)
  if pid <= 0:
    return -1

  var request = SysIpcPacket()
  var reply = SysIpcPacket()
  request.op = SysIpcOpNetTcpReceiveRequest
  request.arg0 = U64(handle)

  if requestIpcReply(pid, addr request, addr reply, SysIpcOpNetTcpReceiveResponse) != 0:
    return -1
  if reply.arg0 == U64(-1'i64):
    return -1

  var copyLen = reply.len
  if copyLen > capacity:
    copyLen = capacity

  let dst = cast[ptr UncheckedArray[U8]](data)
  var i = 0
  while i < int(copyLen):
    dst[i] = U8(reply.data[i])
    inc i

  I32(copyLen)


proc tcpClose*(handle: I32): I32 =
  if handle <= 0:
    return -1

  let pid = servicePidByKind(SysServiceKindNet)
  if pid <= 0:
    return -1

  var request = SysIpcPacket()
  var reply = SysIpcPacket()
  request.op = SysIpcOpNetTcpCloseRequest
  request.arg0 = U64(handle)

  if requestIpcReply(pid, addr request, addr reply, SysIpcOpNetTcpCloseResponse) != 0:
    return -1
  if reply.arg0 == U64(-1'i64):
    return -1

  I32(reply.arg0)
