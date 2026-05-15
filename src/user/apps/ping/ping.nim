import ../../lib/core/io
import ../../lib/ipc/ipc_request
import ../../lib/ipc/service_client
import ../../lib/core/args
import ../../lib/core/strutils
import ../../lib/core/syscall
import ../../lib/net/ipaddr

var
  requestPacket: SysIpcPacket
  responsePacket: SysIpcPacket
  parsedArgs: UserArgs


proc printUsage() =
  write("usage: ping [ip]\n")
  write("default: ping 10.0.2.2\n")


proc user_start*(arg: cstring) {.exportc, cdecl, noreturn.} =
  if not parseUserArgs(arg, parsedArgs):
    printUsage()
    sysExit(1)

  if parsedArgs.argc == 1 and streq(argAt(parsedArgs, 0), "--help"):
    printUsage()
    sysExit(0)

  var ip = U32(0x0a000202'u32)
  if parsedArgs.argc > 1:
    printUsage()
    sysExit(1)

  if parsedArgs.argc == 1 and not parseIpv4Addr(argAt(parsedArgs, 0), ip):
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
  writeIpv4Addr(ip)
  write("\n")

  if requestIpcReply(pid, addr requestPacket, addr responsePacket, SysIpcOpNetPingResponse) != 0:
    write("ping: request failed\n")
    sysExit(1)

  if responsePacket.arg0 == 0:
    write("reply from ")
    writeIpv4Addr(ip)
    write("\n")
    sysExit(0)

  write("timeout from ")
  writeIpv4Addr(ip)
  write("\n")
  sysExit(1)
