import ../../lib/core/io
import ../../lib/net/net_dns
import ../../lib/net/net_http
import ../../lib/core/strutils
import ../../lib/core/syscall

const
  RxCap = 512

var
  url: HttpUrl
  rxBuf: array[RxCap, U8]


proc printUsage() =
  write("usage: curl <http-url|https-url|host|ip>[/path]\n")


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


proc user_start*(arg: cstring) {.exportc, cdecl, noreturn.} =
  if isEmpty(arg):
    printUsage()
    sysExit(1)

  if not parseHttpUrl(arg, url):
    printUsage()
    sysExit(1)

  var ip = U32(0)
  let host = cast[cstring](addr url.host[0])
  let path = cast[cstring](addr url.path[0])
  if not parseIp(host, ip):
    if not resolveA(host, ip):
      write("curl: could not resolve host\n")
      sysExit(1)

  let handle = httpGetStart(ip, url.port, host, path, url.tls)
  if handle <= 0:
    if url.tls:
      write("curl: HTTPS/TLS request failed\n")
    else:
      write("curl: HTTP request failed\n")
    sysExit(1)

  var receivedAny = false
  while true:
    let n = httpRead(handle, addr rxBuf[0], U32(RxCap))
    if n < 0:
      if not receivedAny:
        write("curl: receive failed\n")
        discard httpClose(handle)
        sysExit(1)
      break
    if n == 0:
      break

    receivedAny = true
    discard sysWrite(addr rxBuf[0], U64(n))

  discard httpClose(handle)
  sysExit(0)
