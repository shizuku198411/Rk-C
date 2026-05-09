import ../../lib/io
import ../../lib/syscall
import arp
import config
import icmp
import packet
import state

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


proc handlePacket(packet: ptr SysIpcPacket) =
  if packet.op == SysIpcOpNetPingRequest:
    let targetIp =
      if packet.arg0 == 0:
        GatewayIp
      else:
        U32(packet.arg0 and 0xffffffff'u64)

    let ok = pingHost(net, targetIp)
    sendPingReply(packet.senderPid, ok)


proc pollIpc() =
  while sysIpcTryReceivePacket(addr requestPacket) == 0:
    handlePacket(addr requestPacket)


proc pollRx() =
  let size = sysRawNetRecv(addr net.rxBuf[0], U64(SysNetPacketMax))
  if size <= 0:
    return

  discard handleArpPacket(net, size, net.cachedArpIp, net.cachedArpMac)


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
