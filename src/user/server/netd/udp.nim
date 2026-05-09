import ../../lib/syscall
import arp
import config
import ipv4
import packet
import state

const
  UdpReceiveTimeoutTicks* = 5000


proc nextHopFor*(targetIp: U32): U32 =
  if (targetIp and Netmask) == (LocalIp and Netmask):
    targetIp
  else:
    GatewayIp


proc sendUdp*(net: var NetdState, dstIp: U32, srcPort, dstPort: U16,
              payload: pointer, payloadLen: int): bool =
  if payload == nil:
    return false

  var targetMac: array[SysNetMacLen, U8]
  let nextHopIp = nextHopFor(dstIp)
  if not resolveArp(net, nextHopIp, targetMac):
    return false

  let udpOff = 34
  let udpLen = U16(8 + payloadLen)
  let totalLen = U16(20 + int(udpLen))
  let src = cast[ptr UncheckedArray[U8]](payload)

  var i = 0
  while i < payloadLen:
    net.txBuf[udpOff + 8 + i] = src[i]
    inc i

  copyMacToFrame(net.txBuf, 0, addr targetMac)
  copyMacToFrame(net.txBuf, 6, addr net.mac)
  put16(net.txBuf, 12, EtherTypeIpv4)
  buildIpv4Header(net, totalLen, dstIp, IpProtoUdp)

  put16(net.txBuf, udpOff, srcPort)
  put16(net.txBuf, udpOff + 2, dstPort)
  put16(net.txBuf, udpOff + 4, udpLen)
  put16(net.txBuf, udpOff + 6, 0)

  sendFrame(net.txBuf, U64(14 + int(totalLen)))


proc isUdpPacket*(net: var NetdState, size: I32, srcIp: U32,
                  srcPort, dstPort: U16, payloadOff: var int,
                  payloadLen: var int): bool =
  if size < 42:
    return false
  if get16(addr net.rxBuf, 12) != EtherTypeIpv4:
    return false
  if net.rxBuf[23] != IpProtoUdp:
    return false
  if get32(addr net.rxBuf, 26) != srcIp:
    return false
  if get32(addr net.rxBuf, 30) != LocalIp:
    return false

  let ihl = int(net.rxBuf[14] and 0x0f'u8) * 4
  let udpOff = 14 + ihl
  if size < I32(udpOff + 8):
    return false
  if get16(addr net.rxBuf, udpOff) != srcPort:
    return false
  if get16(addr net.rxBuf, udpOff + 2) != dstPort:
    return false

  let udpLen = int(get16(addr net.rxBuf, udpOff + 4))
  if udpLen < 8:
    return false
  if size < I32(udpOff + udpLen):
    return false

  payloadOff = udpOff + 8
  payloadLen = udpLen - 8
  true


proc isUdpPacketFrom*(net: var NetdState, size: I32, srcIp: U32,
                      srcPort, dstPort: U16, payloadOff: var int,
                      payloadLen: var int): bool =
  if size < 42:
    return false
  if get16(addr net.rxBuf, 12) != EtherTypeIpv4:
    return false
  if net.rxBuf[23] != IpProtoUdp:
    return false

  let packetSrcIp = get32(addr net.rxBuf, 26)
  if srcIp != 0 and packetSrcIp != srcIp:
    return false
  if get32(addr net.rxBuf, 30) != LocalIp:
    return false

  let ihl = int(net.rxBuf[14] and 0x0f'u8) * 4
  let udpOff = 14 + ihl
  if size < I32(udpOff + 8):
    return false
  if srcPort != 0 and get16(addr net.rxBuf, udpOff) != srcPort:
    return false
  if get16(addr net.rxBuf, udpOff + 2) != dstPort:
    return false

  let udpLen = int(get16(addr net.rxBuf, udpOff + 4))
  if udpLen < 8:
    return false
  if size < I32(udpOff + udpLen):
    return false

  payloadOff = udpOff + 8
  payloadLen = udpLen - 8
  true


proc waitUdp*(net: var NetdState, srcIp: U32, srcPort, dstPort: U16,
              outBuf: ptr array[SysIpcMessageMax, char],
              outSrcIp: var U32, outSrcPort: var U16, outLen: var U32): bool =
  var tick = 0
  while tick < UdpReceiveTimeoutTicks:
    let size = sysRawNetRecv(addr net.rxBuf[0], U64(SysNetPacketMax))
    if size > 0:
      var payloadOff = 0
      var payloadLen = 0
      if isUdpPacketFrom(net, size, srcIp, srcPort, dstPort, payloadOff, payloadLen):
        let packetSrcIp = get32(addr net.rxBuf, 26)
        let ihl = int(net.rxBuf[14] and 0x0f'u8) * 4
        let udpOff = 14 + ihl
        let packetSrcPort = get16(addr net.rxBuf, udpOff)
        var copyLen = payloadLen
        if copyLen > SysIpcMessageMax:
          copyLen = SysIpcMessageMax

        var i = 0
        while i < copyLen:
          outBuf[][i] = char(net.rxBuf[payloadOff + i])
          inc i

        outSrcIp = packetSrcIp
        outSrcPort = packetSrcPort
        outLen = U32(copyLen)
        return true

      var mac: array[SysNetMacLen, U8]
      discard handleArpPacket(net, size, nextHopFor(srcIp), mac)

    discard sysSleep(1)
    inc tick

  false
