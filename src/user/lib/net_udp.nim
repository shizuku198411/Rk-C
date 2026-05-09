import ipc_request
import service_client
import syscall


proc packPorts(srcPort, dstPort: U16): U64 =
  (U64(srcPort) shl 16) or U64(dstPort)


proc udpSend*(dstIp: U32, srcPort, dstPort: U16, data: pointer, len: U32): I32 =
  if data == nil or len > SysIpcMessageMax:
    return -1

  let pid = servicePidByKind(SysServiceKindNet)
  if pid <= 0:
    return -1

  var request = SysIpcPacket()
  var reply = SysIpcPacket()
  request.op = SysIpcOpNetUdpSendRequest
  request.arg0 = U64(dstIp)
  request.arg1 = packPorts(srcPort, dstPort)
  request.len = len

  let src = cast[ptr UncheckedArray[U8]](data)
  var i = 0
  while i < int(len):
    request.data[i] = char(src[i])
    inc i

  if requestIpcReply(pid, addr request, addr reply, SysIpcOpNetUdpSendResponse) != 0:
    return -1
  if reply.arg0 != 0:
    return -1

  0


proc udpReceive*(srcIp: U32, srcPort, dstPort: U16, data: pointer,
                 capacity: U32, outSrcIp: ptr U32, outSrcPort: ptr U16): I32 =
  if data == nil or capacity == 0:
    return -1

  let pid = servicePidByKind(SysServiceKindNet)
  if pid <= 0:
    return -1

  var request = SysIpcPacket()
  var reply = SysIpcPacket()
  request.op = SysIpcOpNetUdpReceiveRequest
  request.arg0 = U64(srcIp)
  request.arg1 = packPorts(srcPort, dstPort)

  if requestIpcReply(pid, addr request, addr reply, SysIpcOpNetUdpReceiveResponse) != 0:
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

  if outSrcIp != nil:
    outSrcIp[] = U32(reply.arg0 and 0xffffffff'u64)
  if outSrcPort != nil:
    outSrcPort[] = U16((reply.arg1 shr 16) and 0xffff'u64)

  I32(copyLen)
