import ../../lib/core/io
import ../../lib/net/net_tcp
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


proc parseUint(arg: cstring, value: var U32): bool =
  if isEmpty(arg):
    return false

  var i = 0
  var outValue = U32(0)
  while arg[i] != '\0':
    if arg[i] < '0' or arg[i] > '9':
      return false
    outValue = outValue * 10 + U32(ord(arg[i]) - ord('0'))
    inc i

  value = outValue
  true


proc printUsage() =
  write("usage: tcpcheck <ip> <port>\n")


proc writeI32(value: I32) =
  if value < 0:
    writeChar('-')
    writeUnsigned(U64(-value))
  else:
    writeUnsigned(U64(value))


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
  if not parseIp(ipArg, ip) or not parseUint(portArg, portValue) or portValue > 65535:
    printUsage()
    sysExit(1)

  write("tcpcheck: connecting\n")
  let handle = tcpConnect(ip, U16(0), U16(portValue))
  if handle <= 0:
    write("tcpcheck: connect failed\n")
    sysExit(1)

  write("tcpcheck: connected handle=")
  writeI32(handle)
  write("\n")

  if portValue == 80:
    let sent = tcpSend(handle, addr httpReq[0], U32(HttpReqLen))
    write("tcpcheck: sent=")
    writeI32(sent)
    write("\n")

    let received = tcpReceive(handle, addr rxBuf[0], U32(RxCap))
    write("tcpcheck: received=")
    writeI32(received)
    write("\n")
    if received > 0:
      discard sysWrite(addr rxBuf[0], U64(received))
      write("\n")

  discard tcpClose(handle)
  write("tcpcheck: closed\n")
  sysExit(0)
