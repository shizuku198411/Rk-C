import ./net_udp
import ./netutls
import ../core/strutils
import ../core/syscall

const
  ResolveConfPath = "/etc/resolve.conf"
  DnsServerIp* = U32(0x08080808'u32)
  DnsSourcePort* = U16(49152)
  DnsDestPort* = U16(53)
  DnsQueryIdent* = U16(0x524b)
  DnsPacketMax* = 512

var
  txBuf: array[DnsPacketMax, U8]
  rxBuf: array[DnsPacketMax, U8]


proc put16(buf: var array[DnsPacketMax, U8], off: int, value: U16) =
  buf[off] = U8((value shr 8) and 0xff'u16)
  buf[off + 1] = U8(value and 0xff'u16)


proc get16(buf: ptr array[DnsPacketMax, U8], off: int): U16 =
  (U16(buf[][off]) shl 8) or U16(buf[][off + 1])


proc get32(buf: ptr array[DnsPacketMax, U8], off: int): U32 =
  (U32(buf[][off]) shl 24) or (U32(buf[][off + 1]) shl 16) or
    (U32(buf[][off + 2]) shl 8) or U32(buf[][off + 3])


proc parseNameserverIp(contents: cstring, outIp: var U32): bool =
  var pos: U32 = 0

  let prefix: cstring = "nameserver"
  if not startsWithPrefix(contents, prefix):
    return false
  pos = 10

  while isSpace(contents[pos]):
    inc pos
  
  parseIpv4(contents, pos, outIp)


proc loadNameServerIp(outIp: var U32): bool =
  const BufSize = 64
  var buf: array[BufSize, char]
  let size = sysReadFile(cstring(ResolveConfPath), addr buf[0], BufSize)
  if size < 0:
    return false

  # convert array to cstring
  buf[size] = '\0'
  let contents = cast[cstring](addr buf[0])

  parseNameserverIp(contents, outIp)


proc clearTx() =
  var i = 0
  while i < DnsPacketMax:
    txBuf[i] = 0
    inc i


proc encodeDnsName(off: int, name: cstring): int =
  var pos = 0
  var outPos = off
  let nameLen = int(cstrlen(name))

  while pos < nameLen:
    let labelLenPos = outPos
    var labelLen = 0
    inc outPos

    while pos < nameLen and name[pos] != '.':
      if labelLen >= 63 or outPos >= DnsPacketMax:
        return -1
      txBuf[outPos] = U8(ord(name[pos]))
      inc outPos
      inc pos
      inc labelLen

    if labelLen == 0:
      return -1
    txBuf[labelLenPos] = U8(labelLen)

    if pos < nameLen and name[pos] == '.':
      inc pos

  if outPos >= DnsPacketMax:
    return -1

  txBuf[outPos] = 0
  outPos + 1


proc buildDnsQuery(name: cstring): int =
  clearTx()
  put16(txBuf, 0, DnsQueryIdent)
  put16(txBuf, 2, U16(0x0100))
  put16(txBuf, 4, U16(1))
  put16(txBuf, 6, U16(0))
  put16(txBuf, 8, U16(0))
  put16(txBuf, 10, U16(0))

  let qnameEnd = encodeDnsName(12, name)
  if qnameEnd < 0 or qnameEnd + 4 > DnsPacketMax:
    return -1

  put16(txBuf, qnameEnd, U16(1))
  put16(txBuf, qnameEnd + 2, U16(1))
  qnameEnd + 4


proc skipDnsName(start, limit: int): int =
  var pos = start
  while pos < limit:
    let len = rxBuf[pos]
    if (len and 0xc0'u8) == 0xc0'u8:
      if pos + 1 >= limit:
        return -1
      return pos + 2
    if len == 0:
      return pos + 1
    pos += 1 + int(len)

  -1


proc parseDnsAnswer(size: int, outIp: var U32): bool =
  if size < 12:
    return false
  if get16(addr rxBuf, 0) != DnsQueryIdent:
    return false

  let flags = get16(addr rxBuf, 2)
  if (flags and U16(0x8000)) == 0:
    return false
  if (flags and U16(0x000f)) != 0:
    return false

  let qd = int(get16(addr rxBuf, 4))
  let an = int(get16(addr rxBuf, 6))
  var pos = 12

  var i = 0
  while i < qd:
    pos = skipDnsName(pos, size)
    if pos < 0 or pos + 4 > size:
      return false
    pos += 4
    inc i

  i = 0
  while i < an and pos < size:
    pos = skipDnsName(pos, size)
    if pos < 0 or pos + 10 > size:
      return false

    let rrType = get16(addr rxBuf, pos)
    let rrClass = get16(addr rxBuf, pos + 2)
    let rdLen = int(get16(addr rxBuf, pos + 8))
    pos += 10
    if pos + rdLen > size:
      return false

    if rrType == U16(1) and rrClass == U16(1) and rdLen == 4:
      outIp = get32(addr rxBuf, pos)
      return true

    pos += rdLen
    inc i

  false


proc findAnyARecord(size: int, outIp: var U32): bool =
  var pos = 12
  while pos + 15 < size:
    if (rxBuf[pos] and 0xc0'u8) == 0xc0'u8:
      let rrType = get16(addr rxBuf, pos + 2)
      let rrClass = get16(addr rxBuf, pos + 4)
      let rdLen = int(get16(addr rxBuf, pos + 10))
      if rrType == U16(1) and rrClass == U16(1) and rdLen == 4 and pos + 16 <= size:
        outIp = get32(addr rxBuf, pos + 12)
        return true

      let next = pos + 12 + rdLen
      if next > pos and next <= size:
        pos = next
      else:
        inc pos
    else:
      inc pos

  false


proc resolveA*(name: cstring, outIp: var U32): bool =
  if isEmpty(name):
    return false

  var dnsIp: U32
  if not loadNameServerIp(dnsIp):
    return false

  let queryLen = buildDnsQuery(name)
  if queryLen <= 0:
    return false

  if udpSend(dnsIp, DnsSourcePort, DnsDestPort, addr txBuf[0], U32(queryLen)) != 0:
    return false

  var srcIp = U32(0)
  var srcPort = U16(0)
  let size = udpReceive(dnsIp, DnsDestPort, DnsSourcePort, addr rxBuf[0],
                        U32(DnsPacketMax), addr srcIp, addr srcPort)
  if size <= 0:
    return false

  parseDnsAnswer(int(size), outIp) or findAnyARecord(int(size), outIp)
