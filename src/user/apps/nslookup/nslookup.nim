import ../../lib/core/io
import ../../lib/net/net_dns
import ../../lib/core/strutils
import ../../lib/core/syscall


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


proc user_start*(arg: cstring) {.exportc, cdecl, noreturn.} =
  if isEmpty(arg):
    printUsage()
    sysExit(1)

  write("Server: 8.8.8.8\n")
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
