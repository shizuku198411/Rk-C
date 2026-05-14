import ./net_tcp
import ./net_tls
import ../core/syscall

const
  HttpHostMax* = 96
  HttpPathMax* = 192
  HttpRequestMax* = 512
  HttpDefaultPort* = U16(80)

type
  HttpUrl* = object
    host*: array[HttpHostMax, char]
    path*: array[HttpPathMax, char]
    port*: U16
    tls*: bool


proc clearUrl*(url: var HttpUrl) =
  var i = 0
  while i < HttpHostMax:
    url.host[i] = '\0'
    inc i

  i = 0
  while i < HttpPathMax:
    url.path[i] = '\0'
    inc i

  url.port = HttpDefaultPort
  url.tls = false


proc startsWith(s, prefix: cstring): bool =
  var i = 0
  while prefix[i] != '\0':
    if s[i] != prefix[i]:
      return false
    inc i

  true


proc parsePort(s: cstring, pos: var int, port: var U16): bool =
  if s[pos] < '0' or s[pos] > '9':
    return false

  var value = U32(0)
  while s[pos] >= '0' and s[pos] <= '9':
    value = value * 10 + U32(ord(s[pos]) - ord('0'))
    if value > 65535:
      return false
    inc pos

  port = U16(value)
  true


proc copyPathFrom(url: var HttpUrl, s: cstring, pos: int): bool =
  var i = 0
  while s[pos + i] != '\0' and i < HttpPathMax - 1:
    url.path[i] = s[pos + i]
    inc i

  if s[pos + i] != '\0':
    return false

  url.path[i] = '\0'
  true


proc parseHttpUrl*(arg: cstring, url: var HttpUrl): bool =
  if arg == nil or arg[0] == '\0':
    return false

  clearUrl(url)
  var pos = 0
  if startsWith(arg, "https://"):
    url.tls = true
    url.port = U16(443)
    pos = 8
  if startsWith(arg, "http://"):
    pos = 7

  var hostLen = 0
  while arg[pos] != '\0' and arg[pos] != '/' and arg[pos] != ':':
    if hostLen >= HttpHostMax - 1:
      return false
    url.host[hostLen] = arg[pos]
    inc hostLen
    inc pos

  if hostLen == 0:
    return false

  url.host[hostLen] = '\0'
  if arg[pos] == ':':
    inc pos
    if not parsePort(arg, pos, url.port):
      return false

  if arg[pos] == '\0':
    url.path[0] = '/'
    url.path[1] = '\0'
    return true

  if arg[pos] != '/':
    return false

  copyPathFrom(url, arg, pos)


proc appendChar(buf: pointer, capacity: U32, pos: var U32, ch: char): bool =
  if pos >= capacity:
    return false

  cast[ptr UncheckedArray[U8]](buf)[pos] = U8(ord(ch))
  inc pos
  true


proc appendCString(buf: pointer, capacity: U32, pos: var U32, s: cstring): bool =
  var i = 0
  while s[i] != '\0':
    if not appendChar(buf, capacity, pos, s[i]):
      return false
    inc i

  true


proc buildHttpGetRequest*(host, path: cstring, outBuf: pointer, capacity: U32): I32 =
  if host == nil or path == nil or outBuf == nil or capacity == 0:
    return -1

  var pos = U32(0)
  if not appendCString(outBuf, capacity, pos, "GET "):
    return -1
  if not appendCString(outBuf, capacity, pos, path):
    return -1
  if not appendCString(outBuf, capacity, pos, " HTTP/1.0\r\nHost: "):
    return -1
  if not appendCString(outBuf, capacity, pos, host):
    return -1
  if not appendCString(outBuf, capacity, pos, "\r\nConnection: close\r\n\r\n"):
    return -1

  I32(pos)


proc httpTcpGetStart*(ip: U32, port: U16, host, path: cstring): I32 =
  var reqBuf: array[HttpRequestMax, U8]
  let reqLen = buildHttpGetRequest(host, path, addr reqBuf[0], U32(HttpRequestMax))
  if reqLen <= 0:
    return -1

  let handle = tcpConnect(ip, U16(0), port)
  if handle <= 0:
    return -1

  if tcpSend(handle, addr reqBuf[0], U32(reqLen)) != reqLen:
    discard tcpClose(handle)
    return -1

  handle


proc httpTlsGetStart*(ip: U32, port: U16, host, path: cstring): I32 =
  var reqBuf: array[HttpRequestMax, U8]
  let reqLen = buildHttpGetRequest(host, path, addr reqBuf[0], U32(HttpRequestMax))
  if reqLen <= 0:
    return -1

  let handle = tlsOpen(ip, port, host)
  if handle <= 0:
    return handle

  if tlsSendHandle(handle, addr reqBuf[0], U32(reqLen)) != reqLen:
    discard tlsCloseHandle(handle)
    return -1

  handle


proc httpGetStart*(ip: U32, port: U16, host, path: cstring, tls: bool): I32 =
  if tls:
    return httpTlsGetStart(ip, port, host, path)

  httpTcpGetStart(ip, port, host, path)


proc httpRead*(handle: I32, buf: pointer, capacity: U32): I32 =
  if isTlsHandle(handle):
    return tlsReceiveHandle(handle, buf, capacity)

  tcpReceive(handle, buf, capacity)


proc httpClose*(handle: I32): I32 =
  if isTlsHandle(handle):
    return tlsCloseHandle(handle)

  tcpClose(handle)


proc httpTlsVersionName*(handle: I32): cstring =
  if isTlsHandle(handle):
    return tlsVersionNameHandle(handle)

  cstring("none")


proc httpTlsCipherName*(handle: I32): cstring =
  if isTlsHandle(handle):
    return tlsCipherNameHandle(handle)

  cstring("none")


proc httpTlsLastErrorName*(): cstring =
  tlsLastErrorName()
