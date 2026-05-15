import ../../lib/core/io
import ../../lib/core/cli
import ../../lib/net/net_tcp
import ../../lib/net/ipaddr
import ../../lib/core/args
import ../../lib/core/strutils
import ../../lib/core/syscall

const
  RxCap = 512
  HttpReqLen = 30

var
  rxBuf: array[RxCap, U8]
  parsedArgs: UserArgs
  httpReq = [
    U8(ord('G')), U8(ord('E')), U8(ord('T')), U8(ord(' ')), U8(ord('/')),
    U8(ord(' ')), U8(ord('H')), U8(ord('T')), U8(ord('T')), U8(ord('P')),
    U8(ord('/')), U8(ord('1')), U8(ord('.')), U8(ord('0')), U8(13), U8(10),
    U8(ord('H')), U8(ord('o')), U8(ord('s')), U8(ord('t')), U8(ord(':')),
    U8(ord(' ')), U8(ord('t')), U8(ord('e')), U8(ord('s')), U8(ord('t')),
    U8(13), U8(10), U8(13), U8(10),
  ]


proc printUsage() =
  write("usage: tcpcheck <ip> <port>\n")


proc user_start*(arg: cstring) {.exportc, cdecl, noreturn.} =
  if not parseUserArgs(arg, parsedArgs):
    printUsage()
    sysExit(1)

  if parsedArgs.argc == 1 and streq(argAt(parsedArgs, 0), "--help"):
    printUsage()
    sysExit(0)

  if parsedArgs.argc != 2:
    printUsage()
    sysExit(1)

  let ipArg = argAt(parsedArgs, 0)
  let portArg = argAt(parsedArgs, 1)
  var ip = U32(0)
  var portValue = U32(0)
  if not parseIpv4Addr(ipArg, ip) or not parseU32(portArg, portValue) or portValue > 65535:
    printUsage()
    sysExit(1)

  write("tcpcheck: connecting\n")
  let handle = tcpConnect(ip, U16(0), U16(portValue))
  if handle <= 0:
    write("tcpcheck: connect failed\n")
    sysExit(1)

  write("tcpcheck: connected handle=")
  writeSignedI32(handle)
  write("\n")

  if portValue == 80:
    let sent = tcpSend(handle, addr httpReq[0], U32(HttpReqLen))
    write("tcpcheck: sent=")
    writeSignedI32(sent)
    write("\n")

    let received = tcpReceive(handle, addr rxBuf[0], U32(RxCap))
    write("tcpcheck: received=")
    writeSignedI32(received)
    write("\n")
    if received > 0:
      discard sysWrite(addr rxBuf[0], U64(received))
      write("\n")

  discard tcpClose(handle)
  write("tcpcheck: closed\n")
  sysExit(0)
