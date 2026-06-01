## Runs editor input handling and redraw decisions.
import ../../../lib/core/io
import ../../../lib/core/syscall
import ./buffer
import ./constants
import ./render
import ./terminal


## Handles an ANSI escape sequence for arrow key movement.
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
proc editorLoop*(path: cstring, len: var U64) =
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

      renderStatus(status)
      redrawAfterContentChange(cursor, oldTopLine, topLine, len, false)
