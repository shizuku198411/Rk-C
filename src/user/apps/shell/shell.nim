import ../../lib/io
import ../../lib/pathutils
import ../../lib/strutils
import ../../lib/syscall

const
  LineMax = 80
  ExecArgMax = 160

var
  lineBuf: array[LineMax, char]
  cmdBuf: array[LineMax, char]
  argBuf: array[LineMax, char]
  pathBuf: array[LineMax, char]
  execArgBuf: array[ExecArgMax, char]
  cwdBuf: array[SysProcessCwdMax, char]


proc cstr(buf: var array[LineMax, char]): cstring =
  cast[cstring](addr buf[0])


proc printPrompt() =
  if sysGetCwd(addr cwdBuf[0], U64(SysProcessCwdMax)) < 0:
    cwdBuf[0] = '/'
    cwdBuf[1] = '\0'

  write("Rk-C:")
  write(cast[cstring](addr cwdBuf[0]))
  write("$ ")


proc printBanner() =
  let pid = sysGetPid()
  write("\n[shell] Rk-C shell started pid=")
  writeUnsigned(U64(pid))
  write("\n")
  write("[shell] type 'help' for commands\n")


proc printHelp() =
  write("commands:\n")
  write("  help                       show this help\n")
  write("  cd <path>                  change current directory\n")
  write("  ls [-l] [path]             list directory\n")
  write("  cat <path>                 print file\n")
  write("  mkdir <path>               create directory\n")
  write("  rm <path>                  remove file\n")
  write("  rmdir <path>               remove empty directory\n")
  write("  edit <path>                edit file\n")
  write("  ps                         show process slots\n")
  write("  date                       show current time\n")
  write("  ipc send <pid> <message>   send for IPC message\n")
  write("  ipc receive                wait for IPC message\n")
  write("  kill <pid>                 terminate process\n")
  write("  ticks                      show timer ticks\n")
  write("  bitmap                     show physical page bitmap usage\n")
  write("  <command> &                run command in background\n")
  write("  exit                       exit shell\n")
  write("  shutdown                   shutdown kernel\n")


proc clearArg() =
  var i = 0
  while i < LineMax:
    cmdBuf[i] = '\0'
    argBuf[i] = '\0'
    pathBuf[i] = '\0'
    inc i


proc readLine(): cstring =
  var len = 0
  while true:
    let ch = readChar()
    if ch == '\r' or ch == '\n':
      lineBuf[len] = '\0'
      write("\n")
      return cstr(lineBuf)

    if ch == '\b' or ch == char(127):
      if len > 0:
        dec len
        write("\b \b")
      continue

    if ch < ' ' or ch > '~':
      continue

    if len < LineMax - 1:
      lineBuf[len] = ch
      inc len
      writeChar(ch)


proc skipSpaces(s: cstring, pos: var int) =
  while s[pos] == ' ':
    inc pos


proc parseCommand(line: cstring): bool =
  clearArg()
  var pos = 0
  skipSpaces(line, pos)

  var i = 0
  while line[pos] != '\0' and line[pos] != ' ' and i < LineMax - 1:
    cmdBuf[i] = line[pos]
    inc i
    inc pos
  cmdBuf[i] = '\0'
  if i == 0:
    return false

  skipSpaces(line, pos)
  i = 0
  while line[pos] != '\0' and i < LineMax - 1:
    argBuf[i] = line[pos]
    inc i
    inc pos
  argBuf[i] = '\0'
  true


proc buildBinPath(cmd: cstring): cstring =
  pathBuf[0] = '/'
  pathBuf[1] = 'b'
  pathBuf[2] = 'i'
  pathBuf[3] = 'n'
  pathBuf[4] = '/'
  var i = 0
  while cmd[i] != '\0' and i + 5 < LineMax - 1:
    pathBuf[i + 5] = cmd[i]
    inc i
  pathBuf[i + 5] = '\0'
  cstr(pathBuf)


proc runApp(path: cstring, arg: cstring, background: bool) =
  let pid = sysExec(path, arg, background)
  if pid < 0:
    write("command not found: ")
    write(path)
    write("\n")
    return

  if background:
    write("[bg] pid ")
    writeUnsigned(U64(pid))
    write("\n")
    return

  discard sysWait(pid)


proc changeDirectory(path: cstring) =
  if isEmpty(path):
    write("usage: cd <path>\n")
    return

  let resolved = resolvePath(path)
  if resolved == nil:
    write("cd: path too long\n")
    return

  if sysSetCwd(resolved) != 0:
    write("cd: failed\n")


proc printBitmapInfo() =
  var info: SysBitmapInfo
  if sysGetBitMap(addr info) != 0:
    write("bitmap: failed\n")
    return

  write("bitmap:\n")
  write("  total: ")
  writeUnsigned(info.total)
  write(" pages\n")
  write("  used : ")
  writeUnsigned(info.used)
  write(" pages\n")
  write("  free : ")
  writeUnsigned(info.free)
  write(" pages\n")


proc copyArgChar(pos: var U64, ch: char): bool =
  if pos + 1 >= U64(ExecArgMax):
    return false
  execArgBuf[pos] = ch
  inc pos
  true


proc copyArgCString(pos: var U64, s: cstring): bool =
  var i = U64(0)
  while s[i] != '\0':
    if not copyArgChar(pos, s[i]):
      return false
    inc i
  true


proc finishExecArg(pos: U64): cstring =
  execArgBuf[pos] = '\0'
  cast[cstring](addr execArgBuf[0])


proc resolveShellPath(path: cstring): cstring =
  let resolved = resolvePath(path)
  if resolved == nil:
    write("path too long\n")
  resolved


proc pathCommandArg(arg: cstring): cstring =
  if isEmpty(arg):
    return arg
  resolveShellPath(arg)


proc resolveLsArg(arg: cstring): cstring =
  var pos = 0
  skipSpaces(arg, pos)
  if arg[pos] == '\0':
    return resolveShellPath("")

  if arg[pos] == '-' and arg[pos + 1] == 'l' and
      (arg[pos + 2] == '\0' or arg[pos + 2] == ' '):
    pos += 2
    skipSpaces(arg, pos)

    let rawPath =
      if arg[pos] == '\0': cstring("")
      else: cast[cstring](unsafeAddr arg[pos])
    let resolved = resolveShellPath(rawPath)
    if resolved == nil:
      return nil

    var outPos = U64(0)
    if not copyArgCString(outPos, "-l ") or not copyArgCString(outPos, resolved):
      write("path too long\n")
      return nil
    return finishExecArg(outPos)

  resolveShellPath(cast[cstring](unsafeAddr arg[pos]))


proc prepareExecArg(cmd, arg: cstring): cstring =
  if streq(cmd, "ls"):
    return resolveLsArg(arg)
  if streq(cmd, "cat") or streq(cmd, "mkdir") or streq(cmd, "rm") or
      streq(cmd, "rmdir") or streq(cmd, "edit"):
    return pathCommandArg(arg)
  arg


proc stripBackgroundMarker(): bool =
  var len = 0
  while argBuf[len] != '\0':
    inc len

  while len > 0 and argBuf[len - 1] == ' ':
    dec len
    argBuf[len] = '\0'

  if len == 0 or argBuf[len - 1] != '&':
    return false

  dec len
  argBuf[len] = '\0'
  while len > 0 and argBuf[len - 1] == ' ':
    dec len
    argBuf[len] = '\0'

  true


proc user_start*(arg: cstring) {.exportc, cdecl, noreturn.} =
  discard arg
  printBanner()

  while true:
    printPrompt()
    let cmd = readLine()
    if not parseCommand(cmd):
      continue

    let background = stripBackgroundMarker()

    if streq(cstr(cmdBuf), "help"):
      printHelp()

    elif streq(cstr(cmdBuf), "cd"):
      changeDirectory(cstr(argBuf))

    elif streq(cstr(cmdBuf), "ticks"):
      writeUnsigned(sysTicks())
      write("\n")

    elif streq(cstr(cmdBuf), "bitmap"):
      printBitmapInfo()

    elif streq(cstr(cmdBuf), "exit"):
      sysExit(0)

    elif streq(cstr(cmdBuf), "shutdown"):
      sysShutdown()

    else:
      let execArg = prepareExecArg(cstr(cmdBuf), cstr(argBuf))
      if execArg == nil:
        continue
      runApp(buildBinPath(cstr(cmdBuf)), execArg, background)
