import ../../lib/core/io
import ../../lib/core/syscall
import ../../lib/core/strutils
import ../../lib/net/netutls
import arp
import config
import icmp
import packet
import state
import tcp
import udp
import ipv4


const
  ResolveConfPath = "/etc/resolve.conf"
  InterfaceConfPath = "/etc/interface.conf"


var
  net: NetdState
  requestPacket: SysIpcPacket
  replyPacket: SysIpcPacket

proc sendPingReply(pid: I32, ok: bool) =
  replyPacket = SysIpcPacket()
  replyPacket.op = SysIpcOpNetPingResponse
  if ok:
    replyPacket.arg0 = 0
  else:
    replyPacket.arg0 = U64(-1'i64)

  discard sysIpcSendPacket(pid, addr replyPacket)


proc packedPorts(srcPort, dstPort: U16): U64 =
  (U64(srcPort) shl 16) or U64(dstPort)


proc unpackSrcPort(value: U64): U16 =
  U16((value shr 16) and 0xffff'u64)


proc unpackDstPort(value: U64): U16 =
  U16(value and 0xffff'u64)


proc sendUdpSendReply(pid: I32, ok: bool) =
  replyPacket = SysIpcPacket()
  replyPacket.op = SysIpcOpNetUdpSendResponse
  if ok:
    replyPacket.arg0 = 0
  else:
    replyPacket.arg0 = U64(-1'i64)

  discard sysIpcSendPacket(pid, addr replyPacket)


proc sendUdpReceiveReply(pid: I32, ok: bool, srcIp: U32, srcPort: U16,
                         payload: ptr array[SysIpcMessageMax, char], len: U32) =
  replyPacket = SysIpcPacket()
  replyPacket.op = SysIpcOpNetUdpReceiveResponse
  if ok:
    replyPacket.arg0 = U64(srcIp)
    replyPacket.arg1 = packedPorts(srcPort, U16(0))
    replyPacket.len = len

    var i = 0
    while i < int(len) and i < SysIpcMessageMax:
      replyPacket.data[i] = payload[][i]
      inc i
  else:
    replyPacket.arg0 = U64(-1'i64)
    replyPacket.arg1 = 0
    replyPacket.len = 0

  discard sysIpcSendPacket(pid, addr replyPacket)


proc sendTcpHandleReply(pid: I32, op: U32, handle: I32) =
  replyPacket = SysIpcPacket()
  replyPacket.op = op
  if handle >= 0:
    replyPacket.arg0 = U64(handle)
  else:
    replyPacket.arg0 = U64(-1'i64)

  discard sysIpcSendPacket(pid, addr replyPacket)


proc sendTcpResultReply(pid: I32, op: U32, result: I32) =
  replyPacket = SysIpcPacket()
  replyPacket.op = op
  if result >= 0:
    replyPacket.arg0 = U64(result)
  else:
    replyPacket.arg0 = U64(-1'i64)

  discard sysIpcSendPacket(pid, addr replyPacket)


proc sendTcpReceiveReply(pid: I32, ok: bool, payload: ptr array[SysIpcMessageMax, char],
                         len: U32) =
  replyPacket = SysIpcPacket()
  replyPacket.op = SysIpcOpNetTcpReceiveResponse
  if ok:
    replyPacket.arg0 = 0
    replyPacket.len = len

    var i = 0
    while i < int(len) and i < SysIpcMessageMax:
      replyPacket.data[i] = payload[][i]
      inc i
  else:
    replyPacket.arg0 = U64(-1'i64)
    replyPacket.len = 0

  discard sysIpcSendPacket(pid, addr replyPacket)


proc handlePacket(packet: ptr SysIpcPacket) =
  if packet.op == SysIpcOpNetPingRequest:
    let targetIp =
      if packet.arg0 == 0:
        gatewayIp
      else:
        U32(packet.arg0 and 0xffffffff'u64)

    let ok = pingHost(net, targetIp)
    sendPingReply(packet.senderPid, ok)
  elif packet.op == SysIpcOpNetUdpSendRequest:
    let ok = sendUdp(net, U32(packet.arg0 and 0xffffffff'u64),
                     unpackSrcPort(packet.arg1), unpackDstPort(packet.arg1),
                     addr packet.data[0], int(packet.len))
    sendUdpSendReply(packet.senderPid, ok)
  elif packet.op == SysIpcOpNetUdpReceiveRequest:
    var data: array[SysIpcMessageMax, char]
    var srcIp = U32(0)
    var srcPort = U16(0)
    var len = U32(0)
    let ok = waitUdp(net, U32(packet.arg0 and 0xffffffff'u64),
                     unpackSrcPort(packet.arg1), unpackDstPort(packet.arg1),
                     addr data, srcIp, srcPort, len)
    sendUdpReceiveReply(packet.senderPid, ok, srcIp, srcPort, addr data, len)
  elif packet.op == SysIpcOpNetTcpConnectRequest:
    let handle = tcpConnect(net, U32(packet.arg0 and 0xffffffff'u64),
                            unpackSrcPort(packet.arg1), unpackDstPort(packet.arg1))
    sendTcpHandleReply(packet.senderPid, SysIpcOpNetTcpConnectResponse, handle)
  elif packet.op == SysIpcOpNetTcpSendRequest:
    let sent = tcpSend(net, U32(packet.arg0 and 0xffffffff'u64),
                       addr packet.data[0], int(packet.len))
    sendTcpResultReply(packet.senderPid, SysIpcOpNetTcpSendResponse, sent)
  elif packet.op == SysIpcOpNetTcpReceiveRequest:
    var data: array[SysIpcMessageMax, char]
    var len = U32(0)
    let ok = tcpReceive(net, U32(packet.arg0 and 0xffffffff'u64), addr data, len)
    sendTcpReceiveReply(packet.senderPid, ok, addr data, len)
  elif packet.op == SysIpcOpNetTcpCloseRequest:
    let ok = tcpClose(net, U32(packet.arg0 and 0xffffffff'u64))
    sendTcpResultReply(packet.senderPid, SysIpcOpNetTcpCloseResponse,
                       if ok: I32(0) else: I32(-1))


proc pollIpc() =
  while sysIpcTryReceivePacket(addr requestPacket) == 0:
    handlePacket(addr requestPacket)


proc pollRx() =
  var count = 0
  while count < 32:
    let size = sysRawNetRecv(addr net.rxBuf[0], U64(SysNetPacketMax))
    if size <= 0:
      return

    if handleTcpPacket(net, size):
      inc count
      continue

    discard handleArpPacket(net, size, net.cachedArpIp, net.cachedArpMac)
    inc count


proc loadInterfaceConfig() =
  const
    bufSize = 128
    lineSize = 128
  
  let
    addressPrefix: cstring = "address"
    subnetPrefix: cstring = "subnet"
    gatewayPrefix: cstring = "gateway"

  var
    buf: array[bufSize, char]
    lineBuf: array[lineSize, char]
  let size = sysReadFile(cstring(InterfaceConfPath), addr buf[0], U64(bufSize - 1))
  if size < 0:
    write("[netd] load interface config failed\n")
    sysExit(1)
  
  buf[size] = '\0'
  var pos = 0

  write("[netd] interface:\n")
  while pos < size:
    let lineLen = getLine(addr buf[0], size, pos, addr lineBuf[0], lineSize)
    if lineLen > 0:
      var valuepos: U32 = 0
      let linecstr = cast[cstring](addr lineBuf[0])

      # address
      if startsWithPrefix(linecstr, addressPrefix):
        valuepos = 7
        while isSpace(linecstr[valuepos]):
          inc valuepos
        write("[netd]   address = ")
        write(cast[cstring](addr lineBuf[valuepos]))
        write("\n")
        discard parseIpv4(linecstr, valuepos, interfaceIp)

      # subnet
      elif startsWithPrefix(linecstr, subnetPrefix):
        valuepos = 6
        while isSpace(linecstr[valuepos]):
          inc valuepos
        write("[netd]   subnet  = ")
        write(cast[cstring](addr lineBuf[valuepos]))
        write("\n")
        discard parseIpv4(linecstr, valuepos, subnet)

      # gateway
      elif startsWithPrefix(linecstr, gatewayPrefix):
        valuepos = 7
        while isSpace(linecstr[valuepos]):
          inc valuepos
        write("[netd]   gateway = ")
        write(cast[cstring](addr lineBuf[valuepos]))
        write("\n")
        discard parseIpv4(linecstr, valuepos, gatewayIp)


proc initNetDevice() =
  if sysRawNetInit() != 0:
    write("[netd] virtio-net init failed\n")
    sysExit(1)

  if sysRawNetInfo(addr net.info) != 0:
    write("[netd] virtio-net info failed\n")
    sysExit(1)

  if sysRawNetMac(addr net.mac[0]) != 0:
    write("[netd] virtio-net mac read failed\n")
    sysExit(1)

  write("[netd] virtio-net initialized mmio=")
  writeHex(net.info.mmioBase)
  write(" mac=")
  writeMacValue(addr net.mac)
  write("\n")

  loadInterfaceConfig()


proc checkResolveConf(): bool =
  const bufSize = 64
  var buf: array[bufSize, char]
  sysReadFile(cstring(ResolveConfPath), addr buf[0], bufSize) > 0


proc createResolveConf() =
  let contents: cstring = "nameserver 8.8.8.8"
  if sysWriteFile(cstring(ResolveConfPath), addr contents[0], cstrlen(contents)) != 0:
    write("failed to create ")
    write(cstring(ResolveConfPath))
    write("\n")


proc checkInterfaceConf(): bool =
  const bufSize = 128
  var buf: array[bufSize, char]
  sysReadFile(cstring(InterfaceConfPath), addr buf[0], bufSize) > 0


proc createInterfaceConf() =
  let contents: cstring = "address 10.0.2.15\nsubnet 255.255.255.0\ngateway 10.0.2.2"
  if sysWriteFile(cstring(InterfaceConfPath), addr contents[0], cstrlen(contents)) != 0:
    write("failed to create ")
    write(cstring(InterfaceConfPath))
    write("\n")


proc setupConfigFile() =
  if not checkResolveConf():
    createResolveConf()
  
  if not checkInterfaceConf():
    createInterfaceConf()


proc user_start*(arg: cstring) {.exportc, cdecl, noreturn.} =
  discard arg

  setupConfigFile()

  if sysRawNetInfo(addr net.info) != 0:
    write("[netd] virtio-net detection failed\n")
    sysExit(1)

  if net.info.found == 0:
    write("[netd] virtio-net not found\n")
  else:
    write("[netd] virtio-net found mmio=")
    writeHex(net.info.mmioBase)
    write(" device=")
    writeUnsigned(U64(net.info.deviceId))
    write(" vendor=")
    writeHex(U64(net.info.vendorId))
    write("\n")

  initNetDevice()
  net.tcpNextHandle = 1
  net.tcpNextPort = TcpInitialSourcePort

  while true:
    pollIpc()
    pollRx()
    discard sysSleep(MonitorSleepTicks)
