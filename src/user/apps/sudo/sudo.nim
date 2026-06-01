## Provides the command execution with root privileges.
import ../../lib/core/io
import ../../lib/core/passwd
import ../../lib/core/app
import ../../lib/core/path_buffer
import ../../lib/core/strutils
import ../../lib/core/syscall
import ../../lib/core/userdb
import ../../lib/core/args


const
  CmdMax = 64
  ArgMax = 192
  PathBufMax = 80

var
  cmdBuf: array[CmdMax, char]
  childArgBuf: array[ArgMax, char]
  targetBuf: array[ArgMax, char]
  pathBuf: array[PathBufMax, char]
  parsedArgs: UserArgs

  passwordBuf: array[LoginLineMax, char]


## Advances a parser cursor over whitespace.
proc skipSpaces(arg: cstring, pos: var U32) =
  while isSpace(arg[pos]):
    inc pos


## Splits a command string into executable name and raw child arguments.
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


## Starts one child command with root privilege.
proc execCommandAsRoot(arg: cstring): bool =
  if not parseCommand(arg):
    write("invalid command\n")
    return false

  let path = buildBinPath(
    cast[cstring](addr cmdBuf[0]),
    cast[ptr UncheckedArray[char]](addr pathBuf[0]),
    PathBufMax,
  )
  if path == nil:
    write("command path too long\n")
    return false

  let childArg =
    if childArgBuf[0] == '\0':
      nil
    else:
      cast[cstring](addr childArgBuf[0])

  # password required
  let uid = sysGetUid()
  var entry: PasswdEntry
  if not resolveUid(uid, entry):
    write("failed to reesolve username\n")
    return false

  write("password: ")
  let
    username = cast[cstring](addr entry.name[0])
    password = readLoginLine(passwordBuf, false)
  if not authenticateUser(username, password, entry):
    write("incorrect password\n")
    return false

  let originalUid = sysGetUid()
  let originalGid = sysGetGid()
  if sysSetUser(0, 0) != 0:
    write("failed to switch to root\n")
    return false

  let pid = sysExec(path, childArg, false)
  if pid < 0:
    discard sysSetUser(originalUid, originalGid)
    write("failed to execute ")
    write(path)
    write(" as root.\n")
    return false

  discard sysWait(pid)

  true


## Prints stracectl usage information.
proc printUsage() =
  write("usage:\n")
  write("  sudo <command> [args...]\n")
  write("  sudo --help\n")


## Dispatches trace on, off, pid, or command mode.
proc user_start*(arg: cstring) {.exportc, cdecl, noreturn.} =
  parseArgsOrExit(arg, parsedArgs, printUsage)
  requireMinArgc(parsedArgs, U32(1), printUsage)
  
  var pid: U64
  var targetIndex = U32(0)

  if targetIndex >= parsedArgs.argc:
    printUsage()
    sysExit(1)

  let targetArg = argAt(parsedArgs, targetIndex)

  if cstringEq(targetArg, "--help") and parsedArgs.argc == targetIndex + 1:
    printUsage()
    sysExit(0)

  if parsedArgs.argc != targetIndex + 1 or not parseU64(targetArg, pid):
    if not copyArgvTail(parsedArgs, targetIndex, addr targetBuf[0], U32(ArgMax)):
      printUsage()
      sysExit(1)
      
    if not execCommandAsRoot(cast[cstring](addr targetBuf[0])):
      sysExit(1)

  sysExit(0)
