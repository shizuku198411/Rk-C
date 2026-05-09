import ../../lib/syscall
import config
import packet
import state


proc sendArpRequest*(net: var NetdState, targetIp: U32): bool =
  clearTx(net.txBuf)
  copyBroadcastToFrame(net.txBuf, 0)
  copyMacToFrame(net.txBuf, 6, addr net.mac)
  put16(net.txBuf, 12, EtherTypeArp)
  put16(net.txBuf, 14, U16(1))
  put16(net.txBuf, 16, EtherTypeIpv4)
  net.txBuf[18] = 6
  net.txBuf[19] = 4
  put16(net.txBuf, 20, ArpOpRequest)
  copyMacToFrame(net.txBuf, 22, addr net.mac)
  put32(net.txBuf, 28, LocalIp)
  put32(net.txBuf, 38, targetIp)
  sendFrame(net.txBuf, 42)


proc handleArpPacket*(net: var NetdState, size: I32, targetIp: U32,
                      outMac: var array[SysNetMacLen, U8]): bool =
  if size < 42:
    return false
  if get16(addr net.rxBuf, 12) != EtherTypeArp:
    return false
  if get16(addr net.rxBuf, 20) != ArpOpReply:
    return false
  if get32(addr net.rxBuf, 28) != targetIp:
    return false
  if get32(addr net.rxBuf, 38) != LocalIp:
    return false

  copyMacFromRx(addr net.rxBuf, outMac, 22)
  true


proc resolveArp*(net: var NetdState, targetIp: U32,
                 outMac: var array[SysNetMacLen, U8]): bool =
  if net.cachedArpIp == targetIp:
    var i = 0
    while i < SysNetMacLen:
      outMac[i] = net.cachedArpMac[i]
      inc i
    return true

  if not sendArpRequest(net, targetIp):
    return false

  var tick = 0
  while tick < ArpTimeoutTicks:
    let size = sysRawNetRecv(addr net.rxBuf[0], U64(SysNetPacketMax))
    if size > 0 and handleArpPacket(net, size, targetIp, outMac):
      net.cachedArpIp = targetIp
      var i = 0
      while i < SysNetMacLen:
        net.cachedArpMac[i] = outMac[i]
        inc i
      return true

    discard sysSleep(1)
    inc tick

  false
