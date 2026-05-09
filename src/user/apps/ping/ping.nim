import ../../lib/core/io
import ../../lib/ipc/ipc_request
import ../../lib/ipc/service_client
import ../../lib/core/strutils
import ../../lib/core/syscall

var
  requestPacket: SysIpcPacket
  responsePacket: SysIpcPacket


proc parseOctet(arg: cstring, pos: var int, value: var U32): bool =
  if arg[pos] < '0' or arg[pos] > '9':
    return false

  var outValue = U32(0)
  while arg[pos] >= '0' and arg[pos] <= '9':
    outValue = outValue * 10 + U32(ord(arg[pos]) - ord('0'))
    if outValue > 255:
      return false
    inc pos

  value = outValue
  true


proc parseIp(arg: cstring, ip: var U32): bool =
  var pos = 0
  var a = U32(0)
  var b = U32(0)
  var c = U32(0)
  var d = U32(0)

  if not parseOctet(arg, pos, a):
    return false
  if arg[pos] != '.':
    return false
  inc pos

  if not parseOctet(arg, pos, b):
    return false
  if arg[pos] != '.':
    return false
  inc pos

  if not parseOctet(arg, pos, c):
    return false
  if arg[pos] != '.':
    return false
  inc pos

  if not parseOctet(arg, pos, d):
    return false
  if arg[pos] != '\0':
    return false

  ip = (a shl 24) or (b shl 16) or (c shl 8) or d
  true


proc writeIp(value: U32) =
  writeUnsigned(U64((value shr 24) and 0xff'u32))
  writeChar('.')
  writeUnsigned(U64((value shr 16) and 0xff'u32))
  writeChar('.')
  writeUnsigned(U64((value shr 8) and 0xff'u32))
  writeChar('.')
  writeUnsigned(U64(value and 0xff'u32))


proc printUsage() =
  write("usage: ping [ip]\n")
  write("default: ping 10.0.2.2\n")


proc user_start*(arg: cstring) {.exportc, cdecl, noreturn.} =
  var ip = U32(0x0a000202'u32)
  if not isEmpty(arg):
    if not parseIp(arg, ip):
      printUsage()
      sysExit(1)

  let pid = servicePidByKind(SysServiceKindNet)
  if pid <= 0:
    write("ping: netd unavailable\n")
    sysExit(1)

  requestPacket = SysIpcPacket()
  requestPacket.op = SysIpcOpNetPingRequest
  requestPacket.arg0 = U64(ip)

  write("PING ")
  writeIp(ip)
  write("\n")

  if requestIpcReply(pid, addr requestPacket, addr responsePacket, SysIpcOpNetPingResponse) != 0:
    write("ping: request failed\n")
    sysExit(1)

  if responsePacket.arg0 == 0:
    write("reply from ")
    writeIp(ip)
    write("\n")
    sysExit(0)

  write("timeout from ")
  writeIp(ip)
  write("\n")
  sysExit(1)
