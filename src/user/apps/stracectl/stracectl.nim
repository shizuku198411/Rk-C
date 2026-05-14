import ../../lib/core/io
import ../../lib/core/strutils
import ../../lib/core/syscall

const
  CmdMax = 64
  ArgMax = 192
  PathMax = 80

var
  cmdBuf: array[CmdMax, char]
  childArgBuf: array[ArgMax, char]
  pathBuf: array[PathMax, char]


proc skipSpaces(arg: cstring, pos: var U32) =
  while isSpace(arg[pos]):
    inc pos


proc parseCommand(arg: cstring): bool =
  var pos = U32(0)
  skipSpaces(arg, pos)

  var i = U32(0)
  while arg[pos] != '\0' and not isSpace(arg[pos]):
    if i + 1 >= U32(CmdMax):
      return false

    cmdBuf[i] = arg[pos]
    inc i
    inc pos

  if i == 0:
    return false

  cmdBuf[i] = '\0'
  skipSpaces(arg, pos)

  i = U32(0)
  while arg[pos] != '\0':
    if i + 1 >= U32(ArgMax):
      return false

    childArgBuf[i] = arg[pos]
    inc i
    inc pos

  childArgBuf[i] = '\0'
  true


proc buildBinPath(): cstring =
  pathBuf[0] = '/'
  pathBuf[1] = 'b'
  pathBuf[2] = 'i'
  pathBuf[3] = 'n'
  pathBuf[4] = '/'

  var i = U32(0)
  while cmdBuf[i] != '\0':
    if i + 6 >= U32(PathMax):
      return nil

    pathBuf[i + 5] = cmdBuf[i]
    inc i

  pathBuf[i + 5] = '\0'
  cast[cstring](addr pathBuf[0])


proc traceCommand(arg: cstring, verbose: bool) =
  if not parseCommand(arg):
    write("invalid command\n")
    sysExit(1)

  let path = buildBinPath()
  if path == nil:
    write("command path too long\n")
    sysExit(1)

  let childArg =
    if childArgBuf[0] == '\0':
      nil
    else:
      cast[cstring](addr childArgBuf[0])

  let pid = sysExec(path, childArg, false)
  if pid < 0:
    write("command not found: ")
    write(path)
    write("\n")
    sysExit(1)

  if verbose:
    discard sysTraceCtl(TraceVerbose, 1)

  if sysTraceCtl(TracePid, U64(pid)) < 0:
    write("strace ")
    writeUnsigned(U64(pid))
    write(" failed\n")
    discard sysTraceCtl(TraceVerbose, 0)
    discard sysWait(pid)
    sysExit(1)

  let status = sysWait(pid)
  discard sysTraceCtl(TraceVerbose, 0)
  discard sysTraceCtl(TraceOff, 0)
  sysExit(status)


proc parseVerboseFlag(arg: cstring, outArg: var cstring): bool =
  var pos = U32(0)
  skipSpaces(arg, pos)
  if arg[pos] == '-' and arg[pos + 1] == 'v' and
      (arg[pos + 2] == '\0' or isSpace(arg[pos + 2])):
    pos += 2
    skipSpaces(arg, pos)
    outArg = cast[cstring](cast[U64](arg) + U64(pos))
    return true

  outArg = arg
  false


proc user_start*(arg: cstring) {.exportc, cdecl, noreturn.} =
  if isEmpty(arg):
    write("usage: stracectl [-v] <on|off|<pid>|<command>>\n")
    sysExit(1)
  
  var pid: U64
  var targetArg = arg
  let verbose = parseVerboseFlag(arg, targetArg)

    
  if streq(targetArg, "on"):
    if verbose:
      discard sysTraceCtl(TraceVerbose, 1)
    if sysTraceCtl(TraceOn, 0) < 0:
      write("trace all failed\n")
      sysExit(1)
    write("strace on\n")

  elif streq(targetArg, "off"):
    if sysTraceCtl(TraceOff, 0) < 0:
      write("trace off failed\n")
      sysExit(1)
    write("strace off\n")

  else:
    if not parseU64(targetArg, pid):
      traceCommand(targetArg, verbose)
    if verbose:
      discard sysTraceCtl(TraceVerbose, 1)
    if sysTraceCtl(TracePid, pid) < 0:
      write("strace ")
      writeUnsigned(pid)
      write(" failed\n")
      sysExit(1)
    write("strace ")
    writeUnsigned(pid)
    write(" on\n")


  sysExit(0)
