import ../../lib/core/io
import ../../lib/core/pathutils
import ../../lib/core/strutils
import ../../lib/core/syscall

const
  LineMax = 80
  ExecArgMax = 160
  HistoryMax = 50
  PromptOrange = "\x1b[38;5;208m"
  PromptReset = "\x1b[0m"

var
  lineBuf: array[LineMax, char]
  cmdBuf: array[LineMax, char]
  argBuf: array[LineMax, char]
  pathBuf: array[LineMax, char]
  execArgBuf: array[ExecArgMax, char]
  cwdBuf: array[SysProcessCwdMax, char]

  history: array[HistoryMax, array[LineMax, char]]
  historyPos: int32

proc cstr(buf: var array[LineMax, char]): cstring =
  cast[cstring](addr buf[0])


proc printPrompt() =
  if sysGetCwd(addr cwdBuf[0], U64(SysProcessCwdMax)) < 0:
    cwdBuf[0] = '/'
    cwdBuf[1] = '\0'

  write(PromptOrange)
  write("Rk-C")
  write(PromptReset)
  write(":")
  write(PromptOrange)
  write(cast[cstring](addr cwdBuf[0]))
  write(PromptReset)
  write("$ ")


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
  write("  svc list                   show services\n")
  write("  svc restart <name>         restart service\n")
  write("  ping [ip]                  send ICMP echo request\n")
  write("  nslookup <name>            resolve DNS A record\n")
  write("  curl <url>                 fetch HTTP URL\n")
  write("  tcpcheck <ip> <port>       test TCP connect/send/receive/close\n")
  write("  ticks                      show timer ticks\n")
  write("  traps                      show traps count\n")
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


proc moveCursorLeft() =
  write("\x1b[D")

proc moveCursorRight() =
  write("\x1b[C")


proc clearCurrentLine(len: var int, cursor: var int) =
  while cursor > 0:
    write("\x1b[D")
    dec cursor
  
  var i = 0
  while i < len:
    writeChar(' ')
    inc i
  
  while i > 0:
    write("\x1b[D")
    dec i
  
  len = 0
  cursor = 0


proc lineLen(buf: var array[LineMax, char]): int =
  var i = 0
  while i < LineMax:
    if buf[i] == '\0':
      return i
    inc i
  LineMax - 1


proc loadHistoryLine(
  index: int,
  len: var int,
  cursor: var int
) =
  clearCurrentLine(len, cursor)

  copyMem(addr lineBuf[0], addr history[index][0], LineMax)

  len = lineLen(lineBuf)
  cursor = len

  var i = 0
  while i < len:
    writeChar(lineBuf[i])
    inc i


proc readLine(): cstring =
  var 
    len = 0
    cursor = 0
    historyView = historyPos

  while true:
    let ch = readChar()

    # Enter
    if ch == '\r' or ch == '\n':
      lineBuf[len] = '\0'
      write("\n")
      return cstr(lineBuf)

    # Escape sequence
    if ch == char(27):
      let ch1 = readChar()
      let ch2 = readChar()

      if ch1 == '[':
        case ch2
        of 'D': # Left
          if cursor > 0:
            dec cursor
            moveCursorLeft()
        of 'C': # Right
          if cursor < len:
            inc cursor
            moveCursorRight()
        of 'A': # Up
          if historyPos > 0:
            if historyView > 0:
              dec historyView
              loadHistoryLine(historyView, len, cursor)
        of 'B': # Down
          if historyView < historyPos:
            inc historyView
            if historyView < historyPos:
              loadHistoryLine(historyView, len, cursor)
            else:
              clearCurrentLine(len, cursor)
              lineBuf[0] = '\0'
        else:
          discard

      continue

    # Backspace
    if ch == '\b' or ch == char(127):
      if cursor > 0:
        dec cursor
        dec len

        var i = cursor
        while i < len:
          lineBuf[i] = lineBuf[i + 1]
          inc i

        lineBuf[len] = '\0'

        write("\b")

        i = cursor
        while i < len:
          writeChar(lineBuf[i])
          inc i

        writeChar(' ')

        var back = len - cursor + 1
        while back > 0:
          moveCursorLeft()
          dec back

      continue

    if ch < ' ' or ch > '~':
      continue

    if len < LineMax - 1:
      if cursor == len:
        lineBuf[cursor] = ch
        inc cursor
        inc len
        lineBuf[len] = '\0'
        writeChar(ch)
      else:
        var i = len
        while i > cursor:
          lineBuf[i] = lineBuf[i - 1]
          dec i

        lineBuf[cursor] = ch
        inc cursor
        inc len
        lineBuf[len] = '\0'

        i = cursor - 1
        while i < len:
          writeChar(lineBuf[i])
          inc i

        var back = len - cursor
        while back > 0:
          moveCursorLeft()
          dec back
    
    historyView = historyPos


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


proc printTrapCount() =
  var trapCount: SysTrapCount
  if sysTraps(addr trapCount) != 0:
    write("traps: failed\n")
    return

  write("trap count:\n")
  write("  instruction address misaligned : ")
  writeUnsigned(trapCount.instructionAddressMissaligned)
  write("\n")
  write("  instruction access fault       : ")
  writeUnsigned(trapCount.instructionAccessFault)
  write("\n")
  write("  illegal instruction            : ")
  writeUnsigned(trapCount.illegalInstruction)
  write("\n")
  write("  breakpoint                     : ")
  writeUnsigned(trapCount.breakpoint)
  write("\n")
  write("  load address misaligned        : ")
  writeUnsigned(trapCount.loadAddressMisaligned)
  write("\n")
  write("  load access fault              : ")
  writeUnsigned(trapCount.loadAccessFault)
  write("\n")
  write("  store/amo address misaligned   : ")
  writeUnsigned(trapCount.storeAMOAddressMisaligned)
  write("\n")
  write("  store/amo access fault         : ")
  writeUnsigned(trapCount.storeAMOAccessFault)
  write("\n")
  write("  environment call from u-mode   : ")
  writeUnsigned(trapCount.environmentCallFromUMode)
  write("\n")
  write("  environment call from s-mode   : ")
  writeUnsigned(trapCount.environmentCallFromSMode)
  write("\n")
  write("  instruction page fault         : ")
  writeUnsigned(trapCount.instructionPageFault)
  write("\n")
  write("  load page fault                : ")
  writeUnsigned(trapCount.loadPageFault)
  write("\n")
  write("  store/amo page fault           : ")
  writeUnsigned(trapCount.storeAMOPageFault)
  write("\n")
  write("  supervisor timer               : ")
  writeUnsigned(trapCount.supervisorTimer)
  write("\n")


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

proc printHistory() =
  var pos = 0
  while pos < historyPos:
    write("[")
    writeUnsigned(U64(pos + 1))
    write("] ")
    write(cstr(history[pos]))
    write("\n")
    inc pos

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


proc storeHistory() =
  if historyPos < int32(HistoryMax):
    copyMem(addr history[historyPos][0], addr lineBuf[0], LineMax)
    inc historyPos
  else:
    var i = 1
    while i < HistoryMax:
      copyMem(addr history[i - 1][0], addr history[i][0], LineMax)
      inc i
    copyMem(addr history[HistoryMax - 1][0], addr lineBuf[0], LineMax)


proc user_start*(arg: cstring) {.exportc, cdecl, noreturn.} =
  discard arg

  while true:
    printPrompt()
    let cmd = readLine()
    if not parseCommand(cmd):
      continue

    storeHistory()

    let background = stripBackgroundMarker()

    if streq(cstr(cmdBuf), "help"):
      printHelp()

    elif streq(cstr(cmdBuf), "cd"):
      changeDirectory(cstr(argBuf))

    elif streq(cstr(cmdBuf), "ticks"):
      writeUnsigned(sysTicks())
      write("\n")
    
    elif streq(cstr(cmdBuf), "traps"):
      printTrapCount()

    elif streq(cstr(cmdBuf), "bitmap"):
      printBitmapInfo()

    elif streq(cstr(cmdBuf), "history"):
      printHistory()

    elif streq(cstr(cmdBuf), "exit"):
      sysExit(0)

    elif streq(cstr(cmdBuf), "shutdown"):
      sysShutdown()

    else:
      let execArg = prepareExecArg(cstr(cmdBuf), cstr(argBuf))
      if execArg == nil:
        continue
      runApp(buildBinPath(cstr(cmdBuf)), execArg, background)
