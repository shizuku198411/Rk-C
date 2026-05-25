## Provides a small terminal text editor with save, exit, and cursor movement.
import ../../lib/core/io
import ../../lib/core/args
import ../../lib/core/pathutils
import ../../lib/core/strutils
import ../../lib/core/syscall

const
  BufferMax = 4096
  ScreenRows = 22'u64
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


## Prints edit usage information.
proc printUsage() =
  write("usage: edit <path>\n")
  write("  save: C-x C-s\n")
  write("  exit: C-x C-c\n")
  write("  move: arrow keys\n")


## Writes the current editor buffer to the target path.
proc save(path: cstring, len: U64): bool =
  sysWriteFileMode(path, addr buffer[0], len, SysFsWriteCreate or SysFsWriteOverwrite) == 0


## Loads an existing file into the editor buffer.
proc load(path: cstring): U64 =
  let readLen = sysReadFile(path, addr buffer[0], U64(BufferMax))
  if readLen < 0:
    return 0
  U64(readLen)


## Writes a terminal escape sequence.
proc esc(s: cstring) =
  write(s)


## Moves the terminal cursor to a one-based row and column.
proc gotoPos(row, col: U64) =
  esc("\x1b[")
  writeUnsigned(row)
  write(";")
  writeUnsigned(col)
  write("H")


## Clears the current terminal line.
proc clearLine() =
  esc("\x1b[2K")


## Clears the terminal screen and moves the cursor home.
proc clearScreen() =
  esc("\x1b[2J\x1b[H")


## Finds the start offset of the line containing a buffer position.
proc lineStartAt(pos: U64): U64 =
  var p = pos
  while p > 0 and buffer[p - 1] != '\n':
    dec p
  p


## Finds the end offset of a line starting at the given buffer offset.
proc lineEndAt(start, len: U64): U64 =
  var p = start
  while p < len and buffer[p] != '\n':
    inc p
  p


## Computes the zero-based line number containing a buffer position.
proc lineOf(pos: U64): U64 =
  var line = 0'u64
  var p = 0'u64
  while p < pos:
    if buffer[p] == '\n':
      inc line
    inc p
  line


## Finds the buffer offset for the start of a target line.
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


## Computes the one-based cursor column clamped to the screen width.
proc cursorColumn(cursor: U64): U64 =
  let start = lineStartAt(cursor)
  let col = cursor - start + 1
  if col > ScreenCols: ScreenCols else: col


## Scrolls the visible top line so the cursor remains visible.
proc ensureCursorVisible(cursor: U64, topLine: var U64) =
  let line = lineOf(cursor)
  if line < topLine:
    topLine = line
  elif line >= topLine + EditRows:
    topLine = line - EditRows + 1


## Renders the fixed editor header.
proc renderHeader() =
  gotoPos(HeaderRow, 1)
  esc("\x1b[47;30m")
  clearLine()
  write("Rk-C file editor")
  esc("\x1b[0m")


## Renders the fixed help/status hint row.
proc renderHelp(path: cstring) =
  gotoPos(HelpRow, 1)
  esc("\x1b[47;30m")
  clearLine()
  write("[edit] ")
  write(path)
  write(" | save: C-x C-s | exit: C-x C-c")
  esc("\x1b[0m")


## Renders static rows that do not need to be redrawn on every key press.
proc renderStaticFrame(path: cstring) =
  renderHeader()
  renderHelp(path)


## Renders the bottom status message row.
proc renderStatus(status: cstring) =
  gotoPos(StatusRow, 1)
  clearLine()
  write(status)


## Renders one visible editor row.
proc renderEditorRow(row: U64, len, topLine: U64) =
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


## Redraws only the editor viewport.
proc renderViewport(len, topLine: U64) =
  var row = 0'u64
  while row < EditRows:
    renderEditorRow(row, len, topLine)
    inc row


## Renders the line currently containing the cursor, if visible.
proc renderCursorLine(len, cursor, topLine: U64) =
  let cursorLine = lineOf(cursor)

  if cursorLine < topLine:
    return

  let row = cursorLine - topLine
  if row >= EditRows:
    return

  renderEditorRow(row, len, topLine)


## Restores the terminal cursor to the editor cursor position.
proc renderCursor(cursor, topLine: U64) =
  let cursorLine = lineOf(cursor)

  if cursorLine < topLine:
    gotoPos(EditStartRow, 1)
    return

  let row = cursorLine - topLine
  if row >= EditRows:
    gotoPos(EditStartRow + EditRows - 1, 1)
    return

  gotoPos(EditStartRow + row, cursorColumn(cursor))


## Renders the initial full editor screen.
proc renderInitialScreen(len, cursor, topLine: U64, path, status: cstring) =
  clearScreen()
  renderStaticFrame(path)
  renderViewport(len, topLine)
  renderStatus(status)
  renderCursor(cursor, topLine)


## Inserts one printable character at the cursor.
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


## Deletes the character before the cursor.
##
## Returns true if the deletion may affect multiple visible lines.
proc backspace(len, cursor: var U64): bool =
  if cursor == 0:
    return false

  let removed = buffer[cursor - 1]

  var p = cursor - 1
  while p + 1 < len:
    buffer[p] = buffer[p + 1]
    inc p

  dec cursor
  dec len

  removed == '\n'


## Moves the editor cursor one byte left.
proc moveLeft(cursor: var U64): bool =
  if cursor > 0:
    dec cursor
    return true
  false


## Moves the editor cursor one byte right.
proc moveRight(cursor: var U64, len: U64): bool =
  if cursor < len:
    inc cursor
    return true
  false


## Moves the editor cursor to the previous line.
proc moveUp(cursor: var U64): bool =
  let original = cursor
  let currentStart = lineStartAt(cursor)
  if currentStart == 0:
    return false

  let desiredCol = cursor - currentStart
  let previousEnd = currentStart - 1
  let previousStart = lineStartAt(previousEnd)
  let previousLen = previousEnd - previousStart

  if desiredCol < previousLen:
    cursor = previousStart + desiredCol
  else:
    cursor = previousEnd

  cursor != original


## Moves the editor cursor to the next line.
proc moveDown(cursor: var U64, len: U64): bool =
  let original = cursor
  let currentStart = lineStartAt(cursor)
  let currentEnd = lineEndAt(currentStart, len)
  if currentEnd >= len:
    return false

  let desiredCol = cursor - currentStart
  let nextStart = currentEnd + 1
  let nextEnd = lineEndAt(nextStart, len)
  let nextLen = nextEnd - nextStart

  if desiredCol < nextLen:
    cursor = nextStart + desiredCol
  else:
    cursor = nextEnd

  cursor != original


## Handles an ANSI escape sequence for arrow key movement.
##
## Returns true when the editor cursor moved.
proc handleEscape(cursor: var U64, len: U64): bool =
  let marker = readChar()
  if marker != '[':
    return false

  let code = readChar()
  if code == 'A':
    return moveUp(cursor)
  elif code == 'B':
    return moveDown(cursor, len)
  elif code == 'C':
    return moveRight(cursor, len)
  elif code == 'D':
    return moveLeft(cursor)

  false


## Applies the cheapest redraw strategy after a cursor-only movement.
proc redrawAfterCursorMove(
  cursor: U64,
  oldTopLine: U64,
  topLine: var U64,
  len: U64
) =
  ensureCursorVisible(cursor, topLine)

  if topLine != oldTopLine:
    renderViewport(len, topLine)

  renderCursor(cursor, topLine)


## Applies redraw after a content change.
proc redrawAfterContentChange(
  cursor: U64,
  oldTopLine: U64,
  topLine: var U64,
  len: U64,
  redrawWholeViewport: bool
) =
  ensureCursorVisible(cursor, topLine)

  if redrawWholeViewport or topLine != oldTopLine:
    renderViewport(len, topLine)
  else:
    renderCursorLine(len, cursor, topLine)

  renderCursor(cursor, topLine)


## Runs the editor input loop until save or exit.
proc editorLoop(path: cstring, len: var U64) =
  var cursor = len
  var topLine = 0'u64
  var prefixed = false
  var status: cstring = ""

  ensureCursorVisible(cursor, topLine)
  renderInitialScreen(len, cursor, topLine, path, status)

  while true:
    let ch = readChar()

    if prefixed:
      prefixed = false

      if ch == CtrlS:
        if save(path, len):
          status = "[op] Saved"
        else:
          status = "[op] Save failed"

        renderStatus(status)
        renderCursor(cursor, topLine)
        continue

      elif ch == CtrlC:
        gotoPos(StatusRow, 1)
        clearLine()
        write("[op] Exit\n")
        clearScreen()
        sysExit(0)

      else:
        status = "[op] Unknown Ctrl-X command"
        renderStatus(status)
        renderCursor(cursor, topLine)
        continue

    if ch == CtrlX:
      prefixed = true
      status = "[op] Ctrl-X"
      renderStatus(status)
      renderCursor(cursor, topLine)

    elif ch == Esc:
      let oldTopLine = topLine
      discard handleEscape(cursor, len)

      if status[0] != '\0':
        status = ""
        renderStatus(status)

      redrawAfterCursorMove(cursor, oldTopLine, topLine, len)

    elif ch == '\r' or ch == '\n':
      let oldTopLine = topLine
      status = insertChar('\n', len, cursor)

      if status[0] != '\0':
        renderStatus(status)
      else:
        renderStatus(status)

      redrawAfterContentChange(cursor, oldTopLine, topLine, len, true)

    elif ch == '\b' or ch == char(127):
      let oldTopLine = topLine
      let mergedLines = backspace(len, cursor)

      if status[0] != '\0':
        status = ""
        renderStatus(status)

      redrawAfterContentChange(cursor, oldTopLine, topLine, len, mergedLines)

    elif ch >= ' ' and ch <= '~':
      let oldTopLine = topLine
      status = insertChar(ch, len, cursor)

      if status[0] != '\0':
        renderStatus(status)
      else:
        renderStatus(status)

      redrawAfterContentChange(cursor, oldTopLine, topLine, len, false)


## Parses the file path, loads content, and starts the editor.
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