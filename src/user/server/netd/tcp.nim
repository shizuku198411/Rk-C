import ../../lib/core/syscall
import arp
import config
import ipv4
import packet
import state
import tcp/socket_table
import udp

const
  TcpFlagFin = U8(0x01)
  TcpFlagSyn = U8(0x02)
  TcpFlagPsh = U8(0x08)
  TcpFlagAck = U8(0x10)
  TcpHeaderLen = 20
  TcpSynHeaderLen = 24


proc tcpHeaderLenFor(flags: U8): int =
  if (flags and TcpFlagSyn) != 0:
    TcpSynHeaderLen
  else:
    TcpHeaderLen


proc tcpChecksum(buf: ptr array[SysNetPacketMax, U8], tcpOff: int, tcpLen: int,
                 srcIp, dstIp: U32): U16 =
  var sum = U32(0)
  sum += U32((srcIp shr 16) and 0xffff'u32)
  sum += U32(srcIp and 0xffff'u32)
  sum += U32((dstIp shr 16) and 0xffff'u32)
  sum += U32(dstIp and 0xffff'u32)
  sum += U32(IpProtoTcp)
  sum += U32(tcpLen)

  var i = 0
  while i + 1 < tcpLen:
    sum += U32(get16(buf, tcpOff + i))
    i += 2

  if i < tcpLen:
    sum += U32(buf[][tcpOff + i]) shl 8

  while (sum shr 16) != 0:
    sum = (sum and 0xffff'u32) + (sum shr 16)

  U16(not sum and 0xffff'u32)


proc availableRxSpace(conn: ptr TcpConnection): U32 =
  if conn == nil or conn.rxLen >= U32(TcpRxBufferMax):
    return 0

  U32(TcpRxBufferMax) - conn.rxLen


proc advertisedWindow(conn: ptr TcpConnection): U16 =
  let space = availableRxSpace(conn)
  if space < U32(TcpReceiveWindow):
    U16(space)
  else:
    TcpReceiveWindow


proc sendTcpSegment(net: var NetdState, conn: ptr TcpConnection, flags: U8,
                    payload: pointer, payloadLen: int): bool =
  if conn == nil:
    return false
  if payloadLen < 0 or payloadLen > SysIpcMessageMax:
    return false

  clearTx(net.txBuf)
  copyMacToFrame(net.txBuf, 0, addr conn.remoteMac)
  copyMacToFrame(net.txBuf, 6, addr net.mac)
  put16(net.txBuf, 12, EtherTypeIpv4)

  let tcpOff = 34
  let hdrLen = tcpHeaderLenFor(flags)
  let tcpLen = hdrLen + payloadLen
  let totalLen = U16(20 + tcpLen)
  buildIpv4Header(net, totalLen, conn.remoteIp, IpProtoTcp)

  put16(net.txBuf, tcpOff, conn.localPort)
  put16(net.txBuf, tcpOff + 2, conn.remotePort)
  put32(net.txBuf, tcpOff + 4, conn.seq)
  put32(net.txBuf, tcpOff + 8, conn.ack)
  net.txBuf[tcpOff + 12] = U8(hdrLen div 4) shl 4
  net.txBuf[tcpOff + 13] = flags
  put16(net.txBuf, tcpOff + 14, advertisedWindow(conn))
  put16(net.txBuf, tcpOff + 16, 0)
  put16(net.txBuf, tcpOff + 18, 0)

  if hdrLen == TcpSynHeaderLen:
    net.txBuf[tcpOff + 20] = 2
    net.txBuf[tcpOff + 21] = 4
    put16(net.txBuf, tcpOff + 22, TcpMss)

  if payload != nil and payloadLen > 0:
    let src = cast[ptr UncheckedArray[U8]](payload)
    var i = 0
    while i < payloadLen:
      net.txBuf[tcpOff + hdrLen + i] = src[i]
      inc i

  put16(net.txBuf, tcpOff + 16,
        tcpChecksum(addr net.txBuf, tcpOff, tcpLen, interfaceIp, conn.remoteIp))

  sendFrame(net.txBuf, U64(14 + int(totalLen)))


proc isTcpPacket(net: var NetdState, size: I32, tcpOff: var int,
                 tcpLen: var int): bool =
  if size < 54:
    return false
  if get16(addr net.rxBuf, 12) != EtherTypeIpv4:
    return false
  if net.rxBuf[23] != IpProtoTcp:
    return false
  if get32(addr net.rxBuf, 30) != interfaceIp:
    return false

  let ihl = int(net.rxBuf[14] and 0x0f'u8) * 4
  if ihl < 20:
    return false

  tcpOff = 14 + ihl
  if size < I32(tcpOff + TcpHeaderLen):
    return false

  let hdrLen = int((net.rxBuf[tcpOff + 12] shr 4) and 0x0f'u8) * 4
  if hdrLen < TcpHeaderLen:
    return false
  if size < I32(tcpOff + hdrLen):
    return false

  let ipTotal = int(get16(addr net.rxBuf, 16))
  tcpLen = ipTotal - ihl
  if tcpLen < hdrLen:
    return false
  if size < I32(14 + ipTotal):
    return false

  true


proc compactRxBuffer(conn: ptr TcpConnection) =
  if conn == nil or conn.rxReadOff == 0:
    return

  var i = 0
  while i < int(conn.rxLen):
    conn.rxBuf[i] = conn.rxBuf[int(conn.rxReadOff) + i]
    inc i

  conn.rxReadOff = 0
  conn.rxWriteOff = conn.rxLen


proc appendTcpPayload(conn: ptr TcpConnection, net: var NetdState, payloadOff: int,
                      payloadLen: int): bool =
  if conn == nil or payloadLen <= 0:
    return true
  if U32(payloadLen) > availableRxSpace(conn):
    return false

  if conn.rxWriteOff + U32(payloadLen) > U32(TcpRxBufferMax):
    compactRxBuffer(conn)
  if conn.rxWriteOff + U32(payloadLen) > U32(TcpRxBufferMax):
    return false

  var i = 0
  while i < payloadLen:
    conn.rxBuf[int(conn.rxWriteOff) + i] = net.rxBuf[payloadOff + i]
    inc i

  conn.rxWriteOff += U32(payloadLen)
  conn.rxLen += U32(payloadLen)
  true


proc handleTcpPacket*(net: var NetdState, size: I32): bool =
  var tcpOff = 0
  var tcpLen = 0
  if not isTcpPacket(net, size, tcpOff, tcpLen):
    return false

  let srcIp = get32(addr net.rxBuf, 26)
  let srcPort = get16(addr net.rxBuf, tcpOff)
  let dstPort = get16(addr net.rxBuf, tcpOff + 2)
  let seq = get32(addr net.rxBuf, tcpOff + 4)
  let ack = get32(addr net.rxBuf, tcpOff + 8)
  let flags = net.rxBuf[tcpOff + 13]
  let hdrLen = int((net.rxBuf[tcpOff + 12] shr 4) and 0x0f'u8) * 4
  let payloadLen = tcpLen - hdrLen
  let conn = findTcpByPacket(net, srcIp, srcPort, dstPort)
  if conn == nil:
    return true

  if (flags and TcpFlagAck) != 0:
    conn.ackedSeq = ack

  if conn.state == tcpSynSent and (flags and TcpFlagSyn) != 0 and
      (flags and TcpFlagAck) != 0 and ack == conn.seq + 1'u32:
    conn.ack = seq + 1'u32
    inc conn.seq
    discard sendTcpSegment(net, conn, TcpFlagAck, nil, 0)
    conn.state = tcpEstablished
    return true

  if payloadLen > 0:
    if seq == conn.ack and appendTcpPayload(conn, net, tcpOff + hdrLen, payloadLen):
      conn.ack = seq + U32(payloadLen)
      discard sendTcpSegment(net, conn, TcpFlagAck, nil, 0)
    else:
      discard sendTcpSegment(net, conn, TcpFlagAck, nil, 0)

  if (flags and TcpFlagFin) != 0:
    if seq + U32(payloadLen) == conn.ack:
      inc conn.ack
      conn.finSeen = true
      discard sendTcpSegment(net, conn, TcpFlagAck, nil, 0)
      if conn.state == tcpFinWait1 or conn.state == tcpFinWait2:
        conn.state = tcpTimeWait
      elif conn.state == tcpEstablished:
        conn.state = tcpCloseWait
    else:
      discard sendTcpSegment(net, conn, TcpFlagAck, nil, 0)

  if conn.state == tcpFinWait1 and ack == conn.seq:
    conn.state = tcpFinWait2
  elif conn.state == tcpLastAck and ack == conn.seq:
    releaseTcpConnection(conn)

  true


proc pollTcpAndArp(net: var NetdState, targetIp: U32) =
  let size = sysRawNetRecv(addr net.rxBuf[0], U64(SysNetPacketMax))
  if size <= 0:
    return

  if handleTcpPacket(net, size):
    return

  var mac: array[SysNetMacLen, U8]
  discard handleArpPacket(net, size, nextHopFor(targetIp), mac)


proc tcpConnect*(net: var NetdState, dstIp: U32, srcPort, dstPort: U16): I32 =
  var targetMac: array[SysNetMacLen, U8]
  let nextHopIp = nextHopFor(dstIp)
  if not resolveArp(net, nextHopIp, targetMac):
    return -1

  let conn = allocTcpConnection(net)
  if conn == nil:
    return -1

  conn.state = tcpSynSent
  conn.remoteIp = dstIp
  conn.remoteMac = targetMac
  conn.localPort =
    if srcPort == 0:
      nextTcpPort(net)
    else:
      srcPort
  conn.remotePort = dstPort
  conn.seq = U32(0x524b0000'u32) + conn.handle
  conn.ack = 0

  if not sendTcpSegment(net, conn, TcpFlagSyn, nil, 0):
    releaseTcpConnection(conn)
    return -1

  var tick = 0
  while tick < TcpTimeoutTicks:
    pollTcpAndArp(net, dstIp)
    if conn.state == tcpEstablished:
      return I32(conn.handle)

    discard sysSleep(1)
    inc tick

  releaseTcpConnection(conn)
  -1


proc tcpSend*(net: var NetdState, handle: U32, payload: pointer, payloadLen: int): I32 =
  if payload == nil or payloadLen < 0 or payloadLen > SysIpcMessageMax:
    return -1

  let conn = findTcpByHandle(net, handle)
  if conn == nil or conn.state != tcpEstablished:
    return -1

  let startSeq = conn.seq
  if not sendTcpSegment(net, conn, TcpFlagPsh or TcpFlagAck, payload, payloadLen):
    return -1

  conn.seq += U32(payloadLen)
  var tick = 0
  while tick < TcpTimeoutTicks:
    pollTcpAndArp(net, conn.remoteIp)
    if conn.ackedSeq == conn.seq:
      return I32(payloadLen)

    discard sysSleep(1)
    inc tick

  conn.seq = startSeq
  -1


proc tcpReceive*(net: var NetdState, handle: U32,
                 outBuf: ptr array[SysIpcMessageMax, char], outLen: var U32): bool =
  let conn = findTcpByHandle(net, handle)
  if conn == nil:
    return false

  var tick = 0
  while tick < TcpTimeoutTicks:
    if conn.rxLen > 0:
      var copyLen = conn.rxLen
      if copyLen > U32(SysIpcMessageMax):
        copyLen = U32(SysIpcMessageMax)

      var i = 0
      while i < int(copyLen):
        outBuf[][i] = char(conn.rxBuf[int(conn.rxReadOff) + i])
        inc i

      outLen = copyLen
      conn.rxReadOff += copyLen
      conn.rxLen -= copyLen
      if conn.rxLen == 0:
        conn.rxReadOff = 0
        conn.rxWriteOff = 0
      return true

    if conn.state == tcpCloseWait or conn.state == tcpTimeWait:
      outLen = 0
      return true

    pollTcpAndArp(net, conn.remoteIp)
    discard sysSleep(1)
    inc tick

  false


proc tcpClose*(net: var NetdState, handle: U32): bool =
  let conn = findTcpByHandle(net, handle)
  if conn == nil:
    return false

  if conn.state == tcpEstablished:
    if not sendTcpSegment(net, conn, TcpFlagFin or TcpFlagAck, nil, 0):
      return false
    inc conn.seq
    conn.state = tcpFinWait1
  elif conn.state == tcpCloseWait:
    if not sendTcpSegment(net, conn, TcpFlagFin or TcpFlagAck, nil, 0):
      return false
    inc conn.seq
    conn.state = tcpLastAck
  else:
    releaseTcpConnection(conn)
    return true

  var tick = 0
  while tick < TcpTimeoutTicks:
    pollTcpAndArp(net, conn.remoteIp)
    if conn.state == tcpTimeWait:
      releaseTcpConnection(conn)
      return true
    if conn == nil or not conn.used:
      return true

    discard sysSleep(1)
    inc tick

  releaseTcpConnection(conn)
  true
