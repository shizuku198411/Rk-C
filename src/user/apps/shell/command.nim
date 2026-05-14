import ../../lib/core/io
import ../../lib/core/syscall
import ./state


proc clearArg() =
  var i = 0
  while i < LineMax:
    cmdBuf[i] = '\0'
    argBuf[i] = '\0'
    pathBuf[i] = '\0'
    inc i


proc skipSpaces(s: cstring, pos: var int) =
  while s[pos] == ' ':
    inc pos


proc parseCommand*(line: cstring): bool =
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


proc buildBinPath*(cmd: cstring): cstring =
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


proc runApp*(path: cstring, arg: cstring, background: bool) =
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


proc stripBackgroundMarker*(): bool =
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
