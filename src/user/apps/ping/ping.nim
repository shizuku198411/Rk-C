## Sends an ICMP echo request through netd.
import ../../lib/core/io
import ../../lib/ipc/ipc_request
import ../../lib/ipc/service_client
import ../../lib/core/args
import ../../lib/core/app
import ../../lib/core/syscall
import ../../lib/net/ipaddr

var
  requestPacket: SysIpcPacket
  responsePacket: SysIpcPacket
  parsedArgs: UserArgs


## Prints ping usage information.
proc printUsage() =
  write("usage: ping [ip]\n")
  write("default: ping 10.0.1.1\n")


## Parses the target IP, requests netd ping, and prints the result.
proc user_start*(arg: cstring) {.exportc, cdecl, noreturn.} =
  parseArgsOrExit(arg, parsedArgs, printUsage)
  exitIfHelp(parsedArgs, printUsage)
  requireMaxArgc(parsedArgs, U32(1), printUsage)

  var ip = U32(0x0a000101'u32)
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
