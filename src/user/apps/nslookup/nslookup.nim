import ../../lib/core/io
import ../../lib/net/net_dns
import ../../lib/net/ipaddr
import ../../lib/core/args
import ../../lib/core/strutils
import ../../lib/core/syscall


const
  ResolveConfPath = "/etc/resolve.conf"
  NameserverIpBufSize = 64

var
  nameserverIpBuf: array[NameserverIpBufSize, char]
  parsedArgs: UserArgs

proc printUsage() =
  write("usage: nslookup <name>\n")


proc loadNameserverIp(): cstring =
  let size = sysReadFile(cstring(ResolveConfPath), addr nameserverIpBuf[0], U64(NameserverIpBufSize - 1))
  if size < 0:
    return
  nameserverIpBuf[size] = '\0'
  cast[cstring](addr nameserverIpBuf[11])


proc user_start*(arg: cstring) {.exportc, cdecl, noreturn.} =
  if not parseUserArgs(arg, parsedArgs):
    printUsage()
    sysExit(1)

  if parsedArgs.argc == 1 and streq(argAt(parsedArgs, 0), "--help"):
    printUsage()
    sysExit(0)

  if parsedArgs.argc != 1:
    printUsage()
    sysExit(1)

  let name = argAt(parsedArgs, 0)
  let nameserver = loadNameserverIp()

  write("Server: ")
  write(nameserver)
  write("\n")
  write("Name: ")
  write(name)
  write("\n")

  var ip = U32(0)
  if resolveA(name, ip):
    write("Address: ")
    writeIpv4Addr(ip)
    write("\n")
    sysExit(0)

  write("nslookup: no A record\n")
  sysExit(1)
