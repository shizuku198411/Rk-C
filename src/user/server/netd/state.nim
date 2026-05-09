import ../../lib/syscall

type
  TcpConnState* = enum
    tcpClosed = 0
    tcpSynSent
    tcpEstablished
    tcpFinWait1
    tcpFinWait2
    tcpCloseWait
    tcpLastAck
    tcpTimeWait

  TcpConnection* = object
    used*: bool
    handle*: U32
    state*: TcpConnState
    remoteIp*: U32
    remoteMac*: array[SysNetMacLen, U8]
    localPort*: U16
    remotePort*: U16
    seq*: U32
    ack*: U32
    rxLen*: U32
    rxBuf*: array[SysIpcMessageMax, U8]
    ackedSeq*: U32
    finSeen*: bool

  NetdState* = object
    info*: SysNetDeviceInfo
    mac*: array[SysNetMacLen, U8]
    rxBuf*: array[SysNetPacketMax, U8]
    txBuf*: array[SysNetPacketMax, U8]
    cachedArpIp*: U32
    cachedArpMac*: array[SysNetMacLen, U8]
    pingSeq*: U16
    ipIdent*: U16
    dnsIdent*: U16
    tcpNextHandle*: U32
    tcpNextPort*: U16
    tcpConnections*: array[4, TcpConnection]
