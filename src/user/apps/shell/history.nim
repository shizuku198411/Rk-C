## Provides shell history storage, persistence, and user-specific history paths.
import ../../lib/core/io
import ../../lib/core/syscall
import ../../lib/core/passwd
import ../../lib/core/userdb
import ./state

const
  HistoryFileName = ".history"
  #HistoryPathMax = 128


#var
  #historyPathBuf: array[HistoryPathMax, char]


## Returns the visible length of a fixed shell history entry.
proc lineLen*(buf: var array[LineMax, char]): int =
  var i = 0
  while i < LineMax:
    if buf[i] == '\0':
      return i
    inc i

  LineMax - 1


## Returns the visible length of a heap-backed shell input buffer.
proc lineLen*(buf: ptr UncheckedArray[char], cap: int): int =
  if buf == nil:
    return 0

  var i = 0
  while i < cap:
    if buf[i] == '\0':
      return i
    inc i

  cap - 1


## Clears all in-memory shell history entries.
proc clearHistory*() =
  var i = 0
  while i < HistoryMax:
    var j = 0
    while j < LineMax:
      history[i][j] = '\0'
      inc j
    inc i

  historyPos = 0


## Stores the latest command line and rotates older entries when full.
proc storeHistory*() =
  if lineBuf == nil:
    return

  if lineBuf[0] == '\0':
    return

  if historyPos < int32(HistoryMax):
    copyMem(addr history[historyPos][0], addr lineBuf[0], LineMax)
    inc historyPos
  else:
    var i = 1
    while i < HistoryMax:
      copyMem(addr history[i - 1][0], addr history[i][0], LineMax)
      inc i

    copyMem(addr history[HistoryMax - 1][0], addr lineBuf[0], LineMax)


## Prints history entries with a one-based index.
proc printHistory*() =
  var pos = 0
  while pos < historyPos:
    writeUnsigned(U64(pos + 1))
    write("  ")
    write(cstr(history[pos]))
    write("\n")
    inc pos


proc clearHistoryPathBuf() =
  if historyPathBuf == nil:
    return

  var i = 0
  while i < historyPathBufCap:
    historyPathBuf[i] = '\0'
    inc i


proc appendHistoryPathChar(pos: var int, ch: char): bool =
  if historyPathBuf == nil:
    return false

  if pos + 1 >= historyPathBufCap:
    return false

  historyPathBuf[pos] = ch
  inc pos
  historyPathBuf[pos] = '\0'
  true


proc appendHistoryPathCString(pos: var int, s: cstring): bool =
  if historyPathBuf == nil:
    return false

  if s == nil:
    return true

  var i = 0
  while s[i] != '\0':
    if not appendHistoryPathChar(pos, s[i]):
      return false
    inc i

  true


## Builds the current user's history file path.
##
## root:
##   /.history
##
## user:
##   /home/<user>/.history
proc buildCurrentUserHistoryPath*(): cstring =
  if not initHistoryPathBuffer():
    return nil

  clearHistoryPathBuf()

  let uid = U32(sysGetUid())
  var entry: PasswdEntry

  if not resolveUid(uid, entry):
    return nil

  let home = cast[cstring](addr entry.home[0])

  var pos = 0
  if not appendHistoryPathCString(pos, home):
    return nil

  if pos > 0 and historyPathBuf[pos - 1] != '/':
    if not appendHistoryPathChar(pos, '/'):
      return nil

  if not appendHistoryPathCString(pos, cstring(HistoryFileName)):
    return nil

  historyPathCString()


## Builds the newline-separated history save buffer.
##
## The buffer is heap-backed.
## Returns the number of bytes to write.
proc buildHistorySaveBuf*(): U64 =
  if not initHistorySaveBuffer():
    return 0.U64

  clearHistorySaveBuffer()

  var outPos = 0
  var histIndex = 0

  while histIndex < int(historyPos):
    var charIndex = 0

    while charIndex < LineMax and history[histIndex][charIndex] != '\0':
      if outPos + 1 >= historySaveBufCap:
        return U64(outPos)

      historySaveBuf[outPos] = history[histIndex][charIndex]
      inc outPos
      inc charIndex

    if outPos + 1 >= historySaveBufCap:
      return U64(outPos)

    historySaveBuf[outPos] = '\n'
    inc outPos

    inc histIndex

  U64(outPos)


## Restores in-memory history from the heap-backed save buffer.
proc restoreHistoryFromBuf*(size: U64) =
  clearHistory()

  if historySaveBuf == nil:
    return

  var pos = 0.U64
  var histIndex = 0
  var lineIndex = 0

  while pos < size and pos < U64(historySaveBufCap) and histIndex < HistoryMax:
    let ch = historySaveBuf[int(pos)]

    if ch == '\0':
      break

    if ch == '\n':
      history[histIndex][lineIndex] = '\0'

      if lineIndex > 0:
        inc histIndex

      lineIndex = 0
    else:
      if lineIndex < LineMax - 1:
        history[histIndex][lineIndex] = ch
        inc lineIndex

    pos += 1.U64

  if histIndex < HistoryMax and lineIndex > 0:
    history[histIndex][lineIndex] = '\0'
    inc histIndex

  historyPos = int32(histIndex)


## Saves the current user's shell history.
proc saveHistory*() =
  if not initHistorySaveBuffer():
    write("failed to allocate history save buffer\n")
    return

  let size = buildHistorySaveBuf()
  let path = buildCurrentUserHistoryPath()
  if path == nil:
    write("failed to resolve history path\n")
    return

  if size == 0.U64:
    discard sysWriteFileMode(
      path,
      addr historySaveBuf[0],
      size,
      SysFsWriteCreate or SysFsWriteOverwrite
    )
    return

  if sysWriteFileMode(
    path,
    addr historySaveBuf[0],
    size,
    SysFsWriteCreate or SysFsWriteOverwrite
  ) != 0:
    write("failed to write ")
    write(path)
    write("\n")


## Loads the current user's shell history.
proc loadHistory*() =
  if not initHistorySaveBuffer():
    write("failed to allocate history save buffer\n")
    return

  clearHistorySaveBuffer()

  let path = buildCurrentUserHistoryPath()
  if path == nil:
    clearHistory()
    write("failed to resolve history path\n")
    return

  let size = sysReadFile(
    path,
    addr historySaveBuf[0],
    U64(historySaveBufCap)
  )

  if size <= 0:
    clearHistory()
    return

  restoreHistoryFromBuf(U64(size))
