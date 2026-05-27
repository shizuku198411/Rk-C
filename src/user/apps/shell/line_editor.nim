## Provides editable shell input with cursor movement and history browsing.
import ../../lib/core/io
import ./command_completion
import ./history
import ./state


const
  CtrlL = char(12)
  CtrlU = char(21)


## Moves the terminal cursor one cell to the left.
proc moveCursorLeft() =
  write("\x1b[D")


## Moves the terminal cursor one cell to the right.
proc moveCursorRight() =
  write("\x1b[C")


## Clears the current editable line from the terminal and state buffers.
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

  if lineBuf != nil:
    lineBuf[0] = '\0'


## Replaces the editable line with a selected history entry.
proc loadHistoryLine(
  index: int,
  len: var int,
  cursor: var int
) =
  clearCurrentLine(len, cursor)

  if lineBuf == nil:
    return

  copyMem(addr lineBuf[0], addr history[index][0], LineMax)

  len = lineLen(lineBuf, lineBufCap)
  cursor = len

  var i = 0
  while i < len:
    writeChar(lineBuf[i])
    inc i


## Clears the current terminal line.
proc clearScreen() =
  write("\x1b[2J\x1b[H")


## Reads one editable command line with arrows, backspace, and history keys.
proc readLine*(): cstring =
  if lineBuf == nil:
    return nil

  clearLineBuffer()

  var
    len = 0
    cursor = 0
    historyView = historyPos

  while true:
    let ch = readChar()

    if ch == '\r' or ch == '\n':
      lineBuf[len] = '\0'
      write("\n")
      return lineCString()

    if ch == CtrlL:
      clearScreen()
      lineBuf[len] = '\0'
      return lineCString()

    if ch == CtrlU:
      clearCurrentLine(len, cursor)
      continue

    if ch == char(27):
      let ch1 = readChar()
      let ch2 = readChar()

      if ch1 == '[':
        case ch2
        of 'A':   # up
          if historyPos > 0:
            if historyView > 0:
              dec historyView
              loadHistoryLine(historyView, len, cursor)

        of 'B':   # down
          if historyView < historyPos:
            inc historyView
            if historyView < historyPos:
              loadHistoryLine(historyView, len, cursor)
            else:
              clearCurrentLine(len, cursor)
              lineBuf[0] = '\0'

        of 'C':   # right
          if cursor < len:
            inc cursor
            moveCursorRight()

        of 'D':   # left
          if cursor > 0:
            dec cursor
            moveCursorLeft()
        
        of 'H':   # home
          while cursor > 0:
            dec cursor
            moveCursorLeft()
        
        of 'F':   # end
          while cursor < len:
            inc cursor
            moveCursorRight()

        of '1':   # Home: ESC [ 1 ~
          let tail = readChar()
          if tail == '~':
            while cursor > 0:
              dec cursor
              moveCursorLeft()

        of '4':   # End: ESC [ 4 ~
          let tail = readChar()
          if tail == '~':
            while cursor < len:
              inc cursor
              moveCursorRight()

        of '3':   # Delete: ESC [ 3 ~
          let tail = readChar()
          if tail == '~':
            if cursor < len:
              var i = cursor
              while i + 1 < len:
                lineBuf[i] = lineBuf[i + 1]
                inc i

              dec len
              lineBuf[len] = '\0'

              i = cursor
              while i < len:
                writeChar(lineBuf[i])
                inc i

              writeChar(' ')

              var back = len - cursor + 1
              while back > 0:
                moveCursorLeft()
                dec back

        else:
          discard

      continue

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

    if ch == '\t':
      discard completeCommandAtCursor(len, cursor)
      historyView = historyPos
      continue

    if ch < ' ' or ch > '~':
      continue

    if len < lineBufCap - 1:
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