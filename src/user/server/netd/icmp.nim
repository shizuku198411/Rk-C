import ../../lib/core/io
import ../../lib/core/syscall
import arp
import config
import ipv4
import packet
import state


proc sendIcmpEcho*(net: var NetdState, dstIp: U32,
                   dstMac: ptr array[SysNetMacLen, U8], seq: U16): bool =
  clearTx(net.txBuf)
  copyMacToFrame(net.txBuf, 0, dstMac)
  copyMacToFrame(net.txBuf, 6, addr net.mac)
  put16(net.txBuf, 12, EtherTypeIpv4)

  let payloadLen = 16
  let icmpLen = 8 + payloadLen
  let totalLen = U16(20 + icmpLen)
  buildIpv4Header(net, totalLen, dstIp, IpProtoIcmp)

  let icmpOff = 34
  net.txBuf[icmpOff] = IcmpEchoRequest
  net.txBuf[icmpOff + 1] = 0
  put16(net.txBuf, icmpOff + 2, 0)
  put16(net.txBuf, icmpOff + 4, PingIdent)
  put16(net.txBuf, icmpOff + 6, seq)

  var i = 0
  while i < payloadLen:
    net.txBuf[icmpOff + 8 + i] = U8(ord('a') + (i mod 26))
    inc i

  put16(net.txBuf, icmpOff + 2, checksum(addr net.txBuf, icmpOff, icmpLen))
  sendFrame(net.txBuf, U64(14 + int(totalLen)))


proc isIcmpEchoReply*(net: var NetdState, size: I32, srcIp: U32, seq: U16): bool =
  if size < 42:
    return false
  if get16(addr net.rxBuf, 12) != EtherTypeIpv4:
    return false
  if net.rxBuf[23] != IpProtoIcmp:
    return false
  if get32(addr net.rxBuf, 26) != srcIp:
    return false
  if get32(addr net.rxBuf, 30) != LocalIp:
    return false

  let ihl = int(net.rxBuf[14] and 0x0f'u8) * 4
  let icmpOff = 14 + ihl
  if size < I32(icmpOff + 8):
    return false
  if net.rxBuf[icmpOff] != IcmpEchoReply:
    return false
  if get16(addr net.rxBuf, icmpOff + 4) != PingIdent:
    return false

  get16(addr net.rxBuf, icmpOff + 6) == seq


proc pingHost*(net: var NetdState, targetIp: U32): bool =
  var targetMac: array[SysNetMacLen, U8]
  let nextHopIp =
    if (targetIp and Netmask) == (LocalIp and Netmask):
      targetIp
    else:
      GatewayIp

  if not resolveArp(net, nextHopIp, targetMac):
    write("[netd] arp failed for ")
    writeIp(nextHopIp)
    write("\n")
    return false

  inc net.pingSeq
  if not sendIcmpEcho(net, targetIp, addr targetMac, net.pingSeq):
    return false

  var tick = 0
  while tick < IcmpTimeoutTicks:
    let size = sysRawNetRecv(addr net.rxBuf[0], U64(SysNetPacketMax))
    if size > 0:
      if isIcmpEchoReply(net, size, targetIp, net.pingSeq):
        return true
      discard handleArpPacket(net, size, nextHopIp, targetMac)

    discard sysSleep(1)
    inc tick

  false
