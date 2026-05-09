import ../../../lib/syscall_types
import ../../../lib/types
import ../../mm/usercopy
import ../../net/netdev
import ../../service/registry


proc syscallRawNetInfo*(outInfo: U64): U64 =
  if outInfo == 0 or not currentIsService(serviceNet):
    return U64(-1'i64)

  var info = netdevInfo()
  if copyToUser(outInfo, addr info, U64(sizeof(SysNetDeviceInfo))) != 0:
    return U64(-1'i64)

  0


proc syscallRawNetInit*(): U64 =
  if not currentIsService(serviceNet):
    return U64(-1'i64)

  U64(netdevInit())


proc syscallRawNetMac*(outMac: U64): U64 =
  if outMac == 0 or not currentIsService(serviceNet):
    return U64(-1'i64)

  var mac: array[SysNetMacLen, U8]
  if netdevMac(addr mac[0]) != 0:
    return U64(-1'i64)
  if copyToUser(outMac, addr mac[0], U64(SysNetMacLen)) != 0:
    return U64(-1'i64)

  0


proc syscallRawNetRecv*(outBuf, capacity: U64): U64 =
  if outBuf == 0 or capacity == 0 or capacity > SysNetPacketMax or not currentIsService(serviceNet):
    return U64(-1'i64)

  var packet: array[SysNetPacketMax, U8]
  let size = netdevRecv(addr packet[0], capacity)
  if size < 0:
    return U64(-1'i64)
  if size == 0:
    return U64(0)
  if copyToUser(outBuf, addr packet[0], U64(size)) != 0:
    return U64(-1'i64)

  U64(size)


proc syscallRawNetSend*(inBuf, size: U64): U64 =
  if inBuf == 0 or size == 0 or size > SysNetPacketMax or not currentIsService(serviceNet):
    return U64(-1'i64)

  var packet: array[SysNetPacketMax, U8]
  if copyFromUser(addr packet[0], inBuf, size) != 0:
    return U64(-1'i64)

  let sent = netdevSend(addr packet[0], size)
  if sent < 0:
    return U64(-1'i64)

  U64(sent)
