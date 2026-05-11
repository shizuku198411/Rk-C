import ../../lib/core/io
import ../../lib/net/net_dns
import ../../lib/core/strutils
import ../../lib/core/syscall


const
  ResolveConfPath = "/etc/resolve.conf"
  NameserverIpBufSize = 64

var
  nameserverIpBuf: array[NameserverIpBufSize, char]

proc writeIp(value: U32) =
  writeUnsigned(U64((value shr 24) and 0xff'u32))
  writeChar('.')
  writeUnsigned(U64((value shr 16) and 0xff'u32))
  writeChar('.')
  writeUnsigned(U64((value shr 8) and 0xff'u32))
  writeChar('.')
  writeUnsigned(U64(value and 0xff'u32))


proc printUsage() =
  write("usage: nslookup <name>\n")


proc loadNameserverIp(): cstring =
  let size = sysReadFile(cstring(ResolveConfPath), addr nameserverIpBuf[0], U64(NameserverIpBufSize - 1))
  if size < 0:
    return
  nameserverIpBuf[size] = '\0'
  cast[cstring](addr nameserverIpBuf[11])


proc user_start*(arg: cstring) {.exportc, cdecl, noreturn.} =
  if isEmpty(arg):
    printUsage()
    sysExit(1)

  let nameserver = loadNameserverIp()

  write("Server: ")
  write(nameserver)
  write("\n")
  write("Name: ")
  write(arg)
  write("\n")

  var ip = U32(0)
  if resolveA(arg, ip):
    write("Address: ")
    writeIp(ip)
    write("\n")
    sysExit(0)

  write("nslookup: no A record\n")
  sysExit(1)
