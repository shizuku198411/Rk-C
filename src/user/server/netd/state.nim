import ../../lib/syscall

type
  NetdState* = object
    info*: SysNetDeviceInfo
    mac*: array[SysNetMacLen, U8]
    rxBuf*: array[SysNetPacketMax, U8]
    txBuf*: array[SysNetPacketMax, U8]
    cachedArpIp*: U32
    cachedArpMac*: array[SysNetMacLen, U8]
    pingSeq*: U16
