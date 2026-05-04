import ../../lib/io
import ../../lib/strutils
import ../../lib/syscall

const
  LineMax = 80

var
  lineBuf: array[LineMax, char]
  cmdBuf: array[LineMax, char]
  argBuf: array[LineMax, char]
  pathBuf: array[LineMax, char]

proc cstr(buf: var array[LineMax, char]): cstring =
  cast[cstring](addr buf[0])

proc printPrompt() =
  write("Rk-C:$ ")

proc printBanner() =
  write("\ntype 'help' for commands\n")

proc printHelp() =
  write("commands:\n")
  write("  help                show this help\n")
  write("  ls [-l] [path]      list directory\n")
  write("  cat <path>          print file\n")
  write("  mkdir <path>        create directory\n")
  write("  rm <path>           remove file\n")
  write("  rmdir <path>        remove empty directory\n")
  write("  edit <path>         edit file\n")
  write("  ps                  show process slots\n")
  write("  date                show current time\n")
  write("  ticks               show timer ticks\n")
  write("  exit                exit shell\n")
  write("  shutdown            shutdown kernel\n")

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

proc runApp(path: cstring, arg: cstring) =
  let pid = sysExec(path, arg)
  if pid < 0:
    write("command not found: ")
    write(path)
    write("\n")
    return
  discard sysWait(pid)

proc user_start*(arg: cstring) {.exportc, cdecl, noreturn.} =
  discard arg
  printBanner()

  while true:
    printPrompt()
    let cmd = readLine()
    if not parseCommand(cmd):
      continue

    if streq(cstr(cmdBuf), "help"):
      printHelp()

    elif streq(cstr(cmdBuf), "ticks"):
      writeUnsigned(sysTicks())
      write("\n")

    elif streq(cstr(cmdBuf), "exit"):
      sysExit(0)

    elif streq(cstr(cmdBuf), "shutdown"):
      sysShutdown()
    
    else:
      var arg = cstr(argBuf)
      if streq(cstr(cmdBuf), "ls") and argBuf[0] == '\0':
        arg = "/"
      runApp(buildBinPath(cstr(cmdBuf)), arg)
