import ../../lib/core/io
import ./history
import ./state


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


proc readLine*(): cstring =
  var
    len = 0
    cursor = 0
    historyView = historyPos

  while true:
    let ch = readChar()

    if ch == '\r' or ch == '\n':
      lineBuf[len] = '\0'
      write("\n")
      return cstr(lineBuf)

    if ch == char(27):
      let ch1 = readChar()
      let ch2 = readChar()

      if ch1 == '[':
        case ch2
        of 'D':
          if cursor > 0:
            dec cursor
            moveCursorLeft()
        of 'C':
          if cursor < len:
            inc cursor
            moveCursorRight()
        of 'A':
          if historyPos > 0:
            if historyView > 0:
              dec historyView
              loadHistoryLine(historyView, len, cursor)
        of 'B':
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
