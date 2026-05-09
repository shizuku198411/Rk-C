import ../../lib/core/syscall

const
  MonitorSleepTicks* = U64(1)
  ArpTimeoutTicks* = 200
  IcmpTimeoutTicks* = 300
  DnsTimeoutTicks* = 5000

  EtherTypeIpv4* = U16(0x0800)
  EtherTypeArp* = U16(0x0806)
  ArpOpRequest* = U16(1)
  ArpOpReply* = U16(2)
  IpProtoIcmp* = U8(1)
  IpProtoTcp* = U8(6)
  IpProtoUdp* = U8(17)
  IcmpEchoReply* = U8(0)
  IcmpEchoRequest* = U8(8)

  LocalIp* = U32(0x0a00020f'u32)
  GatewayIp* = U32(0x0a000202'u32)
  DnsServerIp* = U32(0x08080808'u32)
  Netmask* = U32(0xffffff00'u32)
  PingIdent* = U16(0x524b)
  DnsSourcePort* = U16(49152)
  DnsDestPort* = U16(53)
  TcpTimeoutTicks* = 5000
  TcpMaxConnections* = 4
  TcpInitialSourcePort* = U16(50000)
  TcpMss* = U16(512)
  TcpReceiveWindow* = U16(4096)
