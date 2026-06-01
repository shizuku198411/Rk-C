## Renders the editor frame, viewport, status, and cursor.
import ../../../lib/core/io
import ../../../../lib/types
import ./buffer
import ./constants
import ./terminal


var
  renderRowBuf: array[ScreenColsInt, char]


## Renders the fixed editor header.
proc renderHeader*() =
  gotoPos(HeaderRow, 1)
  esc("\x1b[47;30m")
  clearLine()
  write("Rk-C file editor")
  esc("\x1b[0m")


## Renders the fixed help/status hint row.
proc renderHelp*(path: cstring) =
  gotoPos(HelpRow, 1)
  esc("\x1b[47;30m")
  clearLine()
  write("[edit] ")
  write(path)
  write(" | save: C-x C-s | exit: C-x C-c")
  esc("\x1b[0m")


## Renders static rows that do not need to be redrawn on every key press.
proc renderStaticFrame*(path: cstring) =
  renderHeader()
  renderHelp(path)


## Renders the bottom status message row.
proc renderStatus*(status: cstring) =
  gotoPos(StatusRow, 1)
  clearLine()
  write(status)


## Renders one visible editor row.
proc renderEditorRow*(row: U64, len, topLine: U64) =
  gotoPos(EditStartRow + row, 1)
  clearLine()

  let start = findLineStart(topLine + row, len)
  let finish = lineEndAt(start, len)

  var p = start
  var col = 0

  while p < finish and col < ScreenColsInt:
    renderRowBuf[col] = buffer[p]
    inc p
    inc col

  if col > 0:
    writeBuffer(addr renderRowBuf[0], U64(col))


## Redraws only the editor viewport.
proc renderViewport*(len, topLine: U64) =
  var row = 0'u64
  while row < EditRows:
    renderEditorRow(row, len, topLine)
    inc row


## Renders the line currently containing the cursor, if visible.
proc renderCursorLine*(len, cursor, topLine: U64) =
  let cursorLine = lineOf(cursor)

  if cursorLine < topLine:
    return

  let row = cursorLine - topLine
  if row >= EditRows:
    return

  renderEditorRow(row, len, topLine)


## Restores the terminal cursor to the editor cursor position.
proc renderCursor*(cursor, topLine: U64) =
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
proc renderInitialScreen*(len, cursor, topLine: U64, path, status: cstring) =
  clearScreen()
  renderStaticFrame(path)
  renderViewport(len, topLine)
  renderStatus(status)
  renderCursor(cursor, topLine)
