import ../../lib/core/io
import ../../lib/net/net_dns
import ../../lib/net/net_http
import ../../lib/net/ipaddr
import ../../lib/core/args
import ../../lib/core/options
import ../../lib/core/syscall

const
  RxCap = 512
  ArgCap = 256
  HeaderSepLen = 4

let optionSpecs = [
  OptionSpec(short: 'v', long: cstring("tls-info")),
  OptionSpec(short: 'i', long: cstring("include")),
]

var
  url: HttpUrl
  rxBuf: array[RxCap, U8]
  targetArg: array[ArgCap, char]
  parsedArgs: UserArgs
  parsedOptions: ParsedOptions


proc printUsage() =
  write("usage: curl [-v|--tls-info] [-i|--include] <http-url|https-url|host|ip>[/path]\n")
  write("  -v, --tls-info    show negotiated TLS version and cipher\n")
  write("  -i, --include     include HTTP response headers\n")


proc copyArg(dst: var array[ArgCap, char], src: cstring): bool =
  var i = 0
  while src[i] != '\0' and i < ArgCap - 1:
    dst[i] = src[i]
    inc i

  if src[i] != '\0':
    return false

  dst[i] = '\0'
  true


proc headerSepByte(pos: U32): U8 =
  case pos
  of 0: U8('\r')
  of 1: U8('\n')
  of 2: U8('\r')
  else: U8('\n')


proc parseCurlArgs(arg: cstring, verbose: var bool, includeHeaders: var bool,
                   outTarget: var array[ArgCap, char]): bool =
  if not parseUserArgs(arg, parsedArgs):
    return false

  if not parseOptions(parsedArgs, optionSpecs, parsedOptions):
    return false

  if parsedOptions.help or parsedOptions.positionalCount != 1:
    return false

  verbose = hasOption(parsedOptions, 'v')
  includeHeaders = hasOption(parsedOptions, 'i')
  copyArg(outTarget, positionalAt(parsedOptions, 0))


proc printTlsInfo(handle: I32) =
  write("TLS: ")
  write(httpTlsVersionName(handle))
  write("\n")
  write("cipher: ")
  write(httpTlsCipherName(handle))
  write("\n")


proc writeHttpChunk(buf: pointer, len: U32, includeHeaders: bool,
                    headerDone: var bool, matchLen: var U32) =
  if includeHeaders or headerDone:
    discard sysWrite(buf, U64(len))
    return

  let data = cast[ptr UncheckedArray[U8]](buf)
  var i = U32(0)
  while i < len:
    let ch = data[i]
    if ch == headerSepByte(matchLen):
      inc matchLen
      if matchLen == U32(HeaderSepLen):
        headerDone = true
        let bodyStart = i + 1
        if bodyStart < len:
          discard sysWrite(cast[pointer](cast[U64](buf) + U64(bodyStart)),
                           U64(len - bodyStart))
        return
    else:
      if ch == headerSepByte(U32(0)):
        matchLen = 1
      else:
        matchLen = 0

    inc i


proc user_start*(arg: cstring) {.exportc, cdecl, noreturn.} =
  var verbose = false
  var includeHeaders = false
  if not parseCurlArgs(arg, verbose, includeHeaders, targetArg):
    printUsage()
    if parsedOptions.help:
      sysExit(0)
    else:
      sysExit(1)

  if not parseHttpUrl(cast[cstring](addr targetArg[0]), url):
    printUsage()
    sysExit(1)

  var ip = U32(0)
  let host = cast[cstring](addr url.host[0])
  let path = cast[cstring](addr url.path[0])
  if not parseIpv4Addr(host, ip):
    if not resolveA(host, ip):
      write("curl: could not resolve host\n")
      sysExit(1)

  let handle = httpGetStart(ip, url.port, host, path, url.tls, url.portSpecified)
  if handle <= 0:
    if url.tls:
      write("curl: HTTPS/TLS request failed: ")
      write(httpTlsLastErrorName())
      write("\n")
    else:
      write("curl: HTTP request failed\n")
    sysExit(1)

  if verbose and url.tls:
    printTlsInfo(handle)
  elif verbose:
    write("TLS: none\n")
    write("cipher: none\n")

  var receivedAny = false
  var headerDone = false
  var headerMatchLen = U32(0)
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
    writeHttpChunk(addr rxBuf[0], U32(n), includeHeaders, headerDone, headerMatchLen)

  discard httpClose(handle)
  if not receivedAny:
    write("curl: HTTP request failed\n")
    sysExit(1)

  sysExit(0)
