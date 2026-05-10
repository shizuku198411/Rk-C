import ../../lib/core/syscall
import packet
import state

var
  interfaceIp*: U32
  gatewayIp*: U32
  subnet*: U32


proc buildIpv4Header*(net: var NetdState, totalLen: U16, dstIp: U32, proto: U8) =
  inc net.ipIdent
  net.txBuf[14] = 0x45'u8
  net.txBuf[15] = 0
  put16(net.txBuf, 16, totalLen)
  put16(net.txBuf, 18, net.ipIdent)
  put16(net.txBuf, 20, U16(0x4000))
  net.txBuf[22] = 64
  net.txBuf[23] = proto
  put16(net.txBuf, 24, 0)
  put32(net.txBuf, 26, interfaceIp)
  put32(net.txBuf, 30, dstIp)
  put16(net.txBuf, 24, checksum(addr net.txBuf, 14, 20))
