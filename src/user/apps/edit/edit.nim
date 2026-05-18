import ../../lib/core/io
import ../../lib/core/args
import ../../lib/core/pathutils
import ../../lib/core/strutils
import ../../lib/core/syscall

const
  BufferMax = 4096
  ScreenRows = 15'u64
  ScreenCols = 80'u64
  HeaderRow = 1'u64
  EditStartRow = HeaderRow + 1
  HelpRow = ScreenRows - 1
  StatusRow = ScreenRows
  EditRows = ScreenRows - 3
  CtrlC = char(3)
  CtrlS = char(19)
  CtrlX = char(24)
  Esc = char(27)

var buffer: array[BufferMax, char]
var parsedArgs: UserArgs


proc printUsage() =
  write("usage: edit <path>\n")
  write("  save: C-x C-s\n")
  write("  exit: C-x C-c\n")
  write("  move: arrow keys\n")


proc save(path: cstring, len: U64): bool =
  sysWriteFile(path, addr buffer[0], len) == 0


proc load(path: cstring): U64 =
  let readLen = sysReadFile(path, addr buffer[0], U64(BufferMax))
  if readLen < 0:
    return 0
  U64(readLen)


proc esc(s: cstring) =
  write(s)


proc gotoPos(row, col: U64) =
  esc("\x1b[")
  writeUnsigned(row)
  write(";")
  writeUnsigned(col)
  write("H")


proc clearLine() =
  esc("\x1b[2K")


proc clearScreen() =
  esc("\x1b[2J\x1b[H")


proc lineStartAt(pos: U64): U64 =
  var p = pos
  while p > 0 and buffer[p - 1] != '\n':
    dec p
  p


proc lineEndAt(start, len: U64): U64 =
  var p = start
  while p < len and buffer[p] != '\n':
    inc p
  p


proc lineOf(pos: U64): U64 =
  var line = 0'u64
  var p = 0'u64
  while p < pos:
    if buffer[p] == '\n':
      inc line
    inc p
  line


proc findLineStart(targetLine, len: U64): U64 =
  if targetLine == 0:
    return 0

  var line = 0'u64
  var p = 0'u64
  while p < len:
    if buffer[p] == '\n':
      inc line
      if line == targetLine:
        return p + 1
    inc p
  len


proc cursorColumn(cursor: U64): U64 =
  let start = lineStartAt(cursor)
  let col = cursor - start + 1
  if col > ScreenCols: ScreenCols else: col


proc ensureCursorVisible(cursor: U64, topLine: var U64) =
  let line = lineOf(cursor)
  if line < topLine:
    topLine = line
  elif line >= topLine + EditRows:
    topLine = line - EditRows + 1


proc renderHeader() =
  gotoPos(HeaderRow, 1)
  esc("\x1b[47;30m")
  clearLine()
  write("Rk-C file editor")
  esc("\x1b[0m")


proc renderHelp(path: cstring) =
  gotoPos(HelpRow, 1)
  esc("\x1b[47;30m")
  clearLine()
  write("[edit] ")
  write(path)
  write(" | save: C-x C-s | exit: C-x C-c")
  esc("\x1b[0m")


proc renderStatus(status: cstring) =
  gotoPos(StatusRow, 1)
  clearLine()
  write(status)


proc renderBuffer(len, cursor, topLine: U64, path, status: cstring) =
  renderHeader()

  var row = 0'u64
  while row < EditRows:
    gotoPos(EditStartRow + row, 1)
    clearLine()

    let start = findLineStart(topLine + row, len)
    let finish = lineEndAt(start, len)
    var p = start
    var col = 0'u64
    while p < finish and col < ScreenCols:
      writeChar(buffer[p])
      inc p
      inc col

    inc row

  renderHelp(path)
  renderStatus(status)

  let visibleLine = EditStartRow + lineOf(cursor) - topLine
  gotoPos(visibleLine, cursorColumn(cursor))


proc insertChar(ch: char, len, cursor: var U64): cstring =
  if len >= U64(BufferMax):
    return "[warn] Buffer full"

  var p = len
  while p > cursor:
    buffer[p] = buffer[p - 1]
    dec p

  buffer[cursor] = ch
  inc cursor
  inc len
  ""


proc backspace(len, cursor: var U64) =
  if cursor == 0:
    return

  var p = cursor - 1
  while p + 1 < len:
    buffer[p] = buffer[p + 1]
    inc p

  dec cursor
  dec len


proc moveLeft(cursor: var U64) =
  if cursor > 0:
    dec cursor


proc moveRight(cursor: var U64, len: U64) =
  if cursor < len:
    inc cursor


proc moveUp(cursor: var U64) =
  let currentStart = lineStartAt(cursor)
  if currentStart == 0:
    return

  let desiredCol = cursor - currentStart
  let previousEnd = currentStart - 1
  let previousStart = lineStartAt(previousEnd)
  let previousLen = previousEnd - previousStart

  if desiredCol < previousLen:
    cursor = previousStart + desiredCol
  else:
    cursor = previousEnd


proc moveDown(cursor: var U64, len: U64) =
  let currentStart = lineStartAt(cursor)
  let currentEnd = lineEndAt(currentStart, len)
  if currentEnd >= len:
    return

  let desiredCol = cursor - currentStart
  let nextStart = currentEnd + 1
  let nextEnd = lineEndAt(nextStart, len)
  let nextLen = nextEnd - nextStart

  if desiredCol < nextLen:
    cursor = nextStart + desiredCol
  else:
    cursor = nextEnd


proc handleEscape(cursor: var U64, len: U64) =
  let marker = readChar()
  if marker != '[':
    return

  let code = readChar()
  if code == 'A':
    moveUp(cursor)
  elif code == 'B':
    moveDown(cursor, len)
  elif code == 'C':
    moveRight(cursor, len)
  elif code == 'D':
    moveLeft(cursor)


proc editorLoop(path: cstring, len: var U64) =
  var cursor = len
  var topLine = 0'u64
  var prefixed = false
  var status: cstring = ""

  ensureCursorVisible(cursor, topLine)
  clearScreen()
  renderBuffer(len, cursor, topLine, path, status)

  while true:
    let ch = readChar()

    if prefixed:
      prefixed = false
      if ch == CtrlS:
        if save(path, len):
          status = "[op] Saved"
        else:
          status = "[op] Save failed"
      elif ch == CtrlC:
        gotoPos(StatusRow, 1)
        clearLine()
        write("[op] Exit\n")
        clearScreen()
        sysExit(0)
      else:
        status = "[op] Unknown Ctrl-X command"

      ensureCursorVisible(cursor, topLine)
      renderBuffer(len, cursor, topLine, path, status)
      continue

    if ch == CtrlX:
      prefixed = true
      status = "[op] Ctrl-X"
    elif ch == Esc:
      handleEscape(cursor, len)
      status = ""
    elif ch == '\r' or ch == '\n':
      status = insertChar('\n', len, cursor)
    elif ch == '\b' or ch == char(127):
      backspace(len, cursor)
      status = ""
    elif ch >= ' ' and ch <= '~':
      status = insertChar(ch, len, cursor)

    ensureCursorVisible(cursor, topLine)
    renderBuffer(len, cursor, topLine, path, status)


proc user_start*(arg: cstring) {.exportc, cdecl, noreturn.} =
  if not parseUserArgs(arg, parsedArgs):
    printUsage()
    sysExit(1)

  if parsedArgs.argc == 1 and cstringEq(argAt(parsedArgs, 0), "--help"):
    printUsage()
    sysExit(0)

  if parsedArgs.argc != 1:
    printUsage()
    sysExit(1)

  let path = resolvePath(argAt(parsedArgs, 0))
  if path == nil:
    write("edit: path too long\n")
    sysExit(1)

  var len = load(path)
  editorLoop(path, len)
  sysExit(0)
