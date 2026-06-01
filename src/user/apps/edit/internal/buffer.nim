## Manages the editor text buffer, file IO, and cursor calculations.
import ../../../lib/core/syscall
import ./constants


var
  buffer*: array[BufferMax, char]


## Writes the current editor buffer to the target path.
proc save*(path: cstring, len: U64): bool =
  sysWriteFileMode(path, addr buffer[0], len, SysFsWriteCreate or SysFsWriteOverwrite) == 0


## Loads an existing file into the editor buffer.
proc load*(path: cstring): U64 =
  let readLen = sysReadFile(path, addr buffer[0], U64(BufferMax))
  if readLen < 0:
    return 0
  U64(readLen)


## Finds the start offset of the line containing a buffer position.
proc lineStartAt*(pos: U64): U64 =
  var p = pos
  while p > 0 and buffer[p - 1] != '\n':
    dec p
  p


## Finds the end offset of a line starting at the given buffer offset.
proc lineEndAt*(start, len: U64): U64 =
  var p = start
  while p < len and buffer[p] != '\n':
    inc p
  p


## Computes the zero-based line number containing a buffer position.
proc lineOf*(pos: U64): U64 =
  var line = 0'u64
  var p = 0'u64
  while p < pos:
    if buffer[p] == '\n':
      inc line
    inc p
  line


## Finds the buffer offset for the start of a target line.
proc findLineStart*(targetLine, len: U64): U64 =
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
proc cursorColumn*(cursor: U64): U64 =
  let start = lineStartAt(cursor)
  let col = cursor - start + 1
  if col > ScreenCols: ScreenCols else: col


## Scrolls the visible top line so the cursor remains visible.
proc ensureCursorVisible*(cursor: U64, topLine: var U64) =
  let line = lineOf(cursor)
  if line < topLine:
    topLine = line
  elif line >= topLine + EditRows:
    topLine = line - EditRows + 1


## Inserts one printable character at the cursor.
proc insertChar*(ch: char, len, cursor: var U64): cstring =
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
proc backspace*(len, cursor: var U64): bool =
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
proc moveLeft*(cursor: var U64): bool =
  if cursor > 0:
    dec cursor
    return true
  false


## Moves the editor cursor one byte right.
proc moveRight*(cursor: var U64, len: U64): bool =
  if cursor < len:
    inc cursor
    return true
  false


## Moves the editor cursor to the previous line.
proc moveUp*(cursor: var U64): bool =
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
proc moveDown*(cursor: var U64, len: U64): bool =
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
