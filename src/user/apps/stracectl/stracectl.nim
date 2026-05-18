import ../../lib/core/io
import ../../lib/core/args
import ../../lib/core/strutils
import ../../lib/core/syscall

const
  CmdMax = 64
  ArgMax = 192
  PathMax = 80

var
  cmdBuf: array[CmdMax, char]
  childArgBuf: array[ArgMax, char]
  targetBuf: array[ArgMax, char]
  pathBuf: array[PathMax, char]
  parsedArgs: UserArgs


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


proc printUsage() =
  write("usage:\n")
  write("  stracectl on\n")
  write("  stracectl off\n")
  write("  stracectl [-v] <pid>\n")
  write("  stracectl [-v] <command> [args...]\n")
  write("\n")
  write("options:\n")
  write("  -v    include verbose syscall details\n")


proc user_start*(arg: cstring) {.exportc, cdecl, noreturn.} =
  if not parseUserArgs(arg, parsedArgs) or parsedArgs.argc == 0:
    printUsage()
    sysExit(1)
  
  var pid: U64
  var targetIndex = U32(0)
  var verbose = false
  if cstringEq(argAt(parsedArgs, 0), "-v"):
    verbose = true
    targetIndex = 1

  if targetIndex >= parsedArgs.argc:
    printUsage()
    sysExit(1)

  let targetArg = argAt(parsedArgs, targetIndex)

  if cstringEq(targetArg, "--help") and parsedArgs.argc == targetIndex + 1:
    printUsage()
    sysExit(0)

    
  if cstringEq(targetArg, "on") and parsedArgs.argc == targetIndex + 1:
    if verbose:
      discard sysTraceCtl(TraceVerbose, 1)
    if sysTraceCtl(TraceOn, 0) < 0:
      write("trace all failed\n")
      sysExit(1)
    write("strace on\n")

  elif cstringEq(targetArg, "off") and parsedArgs.argc == targetIndex + 1:
    if sysTraceCtl(TraceOff, 0) < 0:
      write("trace off failed\n")
      sysExit(1)
    write("strace off\n")

  else:
    if parsedArgs.argc != targetIndex + 1 or not parseU64(targetArg, pid):
      if not copyArgvTail(parsedArgs, targetIndex, addr targetBuf[0], U32(ArgMax)):
        printUsage()
        sysExit(1)

      traceCommand(cast[cstring](addr targetBuf[0]), verbose)
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
