import ../../lib/io
import ../../lib/syscall
import arp
import config
import icmp
import packet
import state
import udp

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


proc handlePacket(packet: ptr SysIpcPacket) =
  if packet.op == SysIpcOpNetPingRequest:
    let targetIp =
      if packet.arg0 == 0:
        GatewayIp
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


proc pollIpc() =
  while sysIpcTryReceivePacket(addr requestPacket) == 0:
    handlePacket(addr requestPacket)


proc pollRx() =
  var count = 0
  while count < 32:
    let size = sysRawNetRecv(addr net.rxBuf[0], U64(SysNetPacketMax))
    if size <= 0:
      return

    discard handleArpPacket(net, size, net.cachedArpIp, net.cachedArpMac)
    inc count


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
  write(" ip=")
  writeIp(LocalIp)
  write("\n")


proc user_start*(arg: cstring) {.exportc, cdecl, noreturn.} =
  discard arg

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

  while true:
    pollIpc()
    pollRx()
    discard sysSleep(MonitorSleepTicks)
