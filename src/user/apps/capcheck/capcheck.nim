import ../../../lib/syscall_caps
import ../../lib/core/args
import ../../lib/core/io
import ../../lib/core/strutils
import ../../lib/core/syscall
import ../../lib/ipc/ipc_request
import ../../lib/ipc/service_client


const
  StatusBufSize = U64(512)
  PathBufSize = 32
  ProcInfoCap = 2

var
  parsedArgs: UserArgs
  statusBuf: array[StatusBufSize, char]
  pathBuf: array[PathBufSize, char]
  procInfos: array[ProcInfoCap, SysProcessInfo]
  netInfo: SysNetDeviceInfo
  requestPacket: SysIpcPacket
  responsePacket: SysIpcPacket


proc printUsage() =
  write("usage: capcheck\n")


proc appendCString(buf: var array[PathBufSize, char], pos: var U32, s: cstring) =
  var i = U32(0)
  while s[i] != '\0' and pos + U32(1) < U32(PathBufSize):
    buf[pos] = s[i]
    inc pos
    inc i
  buf[pos] = '\0'


proc appendU32(buf: var array[PathBufSize, char], pos: var U32, value: U32) =
  var
    tmp: array[16, char]
    n = value
    len = U32(0)

  if n == U32(0):
    if pos + U32(1) < U32(PathBufSize):
      buf[pos] = '0'
      inc pos
      buf[pos] = '\0'
    return

  while n > U32(0) and len < U32(16):
    tmp[len] = char(ord('0') + int(n mod U32(10)))
    n = n div U32(10)
    inc len

  while len > U32(0) and pos + U32(1) < U32(PathBufSize):
    dec len
    buf[pos] = tmp[len]
    inc pos
    buf[pos] = '\0'


proc buildStatusPath(pid: I32) =
  var i = U32(0)
  while i < U32(PathBufSize):
    pathBuf[i] = '\0'
    inc i

  var pos = U32(0)
  appendCString(pathBuf, pos, cstring("/proc/"))
  appendU32(pathBuf, pos, U32(pid))
  appendCString(pathBuf, pos, cstring("/status"))


proc contains(buf: ptr UncheckedArray[char], needle: cstring): bool =
  var i = U32(0)
  while buf[i] != '\0':
    var j = U32(0)
    while needle[j] != '\0' and buf[i + j] == needle[j]:
      inc j
    if needle[j] == '\0':
      return true
    inc i

  false


proc fail(msg: cstring) {.noreturn.} =
  write("capcheck: FAIL ")
  write(msg)
  write("\n")
  sysExit(1)


proc expectDenied(result: I32, name: cstring) =
  if result >= 0:
    fail(name)
  write("capcheck: ")
  write(name)
  write(" denied\n")


proc expectForgedKillDenied(pid: I32) =
  let processManager = servicePidByKind(SysServiceKindProcess)
  if processManager <= 0:
    fail(cstring("process service"))

  requestPacket = SysIpcPacket()
  requestPacket.op = SysIpcOpProcKillRequest
  requestPacket.arg0 = U64(pid)
  requestPacket.capabilityMask = SysCapProcessKill

  if requestIpcReply(
      processManager,
      addr requestPacket,
      addr responsePacket,
      SysIpcOpProcKillResponse,
    ) != 0:
    fail(cstring("forged kill reply"))

  if I32(responsePacket.arg0) == 0:
    fail(cstring("forged kill accepted"))

  write("capcheck: forged kill denied\n")


proc runCheck() =
  let pid = sysGetPid()
  if pid <= 0:
    fail(cstring("getpid"))

  buildStatusPath(pid)
  let readLen = sysReadFile(cast[cstring](addr pathBuf[0]), addr statusBuf[0], StatusBufSize - U64(1))
  if readLen <= 0:
    fail(cstring("read status"))
  statusBuf[U64(readLen)] = '\0'

  if not contains(cast[ptr UncheckedArray[char]](addr statusBuf[0]), cstring("requested_caps: 0x3f")):
    fail(cstring("requested caps missing"))
  write("capcheck: requested caps visible\n")

  if not contains(cast[ptr UncheckedArray[char]](addr statusBuf[0]), cstring("sys_raw_fs")):
    fail(cstring("requested cap names missing"))
  write("capcheck: requested cap names visible\n")

  if not contains(cast[ptr UncheckedArray[char]](addr statusBuf[0]), cstring("caps: 0x0 (none)")):
    fail(cstring("granted caps not stripped"))
  write("capcheck: granted caps stripped\n")

  expectDenied(sysRawNetInfo(addr netInfo), cstring("raw_net"))
  expectDenied(sysPs(addr procInfos[0], U64(ProcInfoCap)), cstring("process_list"))
  expectForgedKillDenied(pid)

  write("capcheck: ok\n")
  sysExit(0)


proc user_start*(arg: cstring) {.exportc, cdecl, noreturn.} =
  if not parseUserArgs(arg, parsedArgs):
    printUsage()
    sysExit(1)

  if parsedArgs.argc == 1 and streq(argAt(parsedArgs, 0), "--help"):
    printUsage()
    sysExit(0)

  if parsedArgs.argc != 0:
    printUsage()
    sysExit(1)

  runCheck()
