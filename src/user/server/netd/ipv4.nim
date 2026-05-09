import ../../lib/syscall
import config
import packet
import state


proc buildIpv4Header*(net: var NetdState, totalLen: U16, dstIp: U32) =
  net.txBuf[14] = 0x45'u8
  net.txBuf[15] = 0
  put16(net.txBuf, 16, totalLen)
  put16(net.txBuf, 18, net.pingSeq)
  put16(net.txBuf, 20, U16(0x4000))
  net.txBuf[22] = 64
  net.txBuf[23] = IpProtoIcmp
  put16(net.txBuf, 24, 0)
  put32(net.txBuf, 26, LocalIp)
  put32(net.txBuf, 30, dstIp)
  put16(net.txBuf, 24, checksum(addr net.txBuf, 14, 20))
