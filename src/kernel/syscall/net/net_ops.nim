## Implements raw network device syscall handlers.
import ../../../lib/syscall_types
import ../../../lib/types
import ../../lib/syscall_out
import ../../mm/usercopy
import ../../net/netdev
import ../syscall_cap


## Handles the raw net info syscall operation.
proc syscallRawNetInfo*(outInfo: U64): U64 =
  if outInfo == 0 or not canSyscallRawNet():
    return U64(-1'i64)

  var info = netdevInfo()
  if not copyOutObject(outInfo, info):
    return U64(-1'i64)

  0


## Handles the raw net init syscall operation.
proc syscallRawNetInit*(): U64 =
  if not canSyscallRawNet():
    return U64(-1'i64)

  U64(netdevInit())


## Handles the raw net mac syscall operation.
proc syscallRawNetMac*(outMac: U64): U64 =
  if outMac == 0 or not canSyscallRawNet():
    return U64(-1'i64)

  var mac: array[SysNetMacLen, U8]
  if netdevMac(addr mac[0]) != 0:
    return U64(-1'i64)
  if not copyOutBuffer(outMac, addr mac[0], U64(SysNetMacLen)):
    return U64(-1'i64)

  0


## Handles the raw net recv syscall operation.
proc syscallRawNetRecv*(outBuf, capacity: U64): U64 =
  if outBuf == 0 or capacity == 0 or capacity > SysNetPacketMax or not canSyscallRawNet():
    return U64(-1'i64)

  var packet: array[SysNetPacketMax, U8]
  let size = netdevRecv(addr packet[0], capacity)
  if size < 0:
    return U64(-1'i64)
  if size == 0:
    return U64(0)
  if not copyOutBuffer(outBuf, addr packet[0], U64(size)):
    return U64(-1'i64)

  U64(size)


## Handles the raw net send syscall operation.
proc syscallRawNetSend*(inBuf, size: U64): U64 =
  if inBuf == 0 or size == 0 or size > SysNetPacketMax or not canSyscallRawNet():
    return U64(-1'i64)

  var packet: array[SysNetPacketMax, U8]
  if copyFromUser(addr packet[0], inBuf, size) != 0:
    return U64(-1'i64)

  let sent = netdevSend(addr packet[0], size)
  if sent < 0:
    return U64(-1'i64)

  U64(sent)
