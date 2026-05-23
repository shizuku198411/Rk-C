## Manages per-user shell history loading, saving, printing, and rotation.
import ../../lib/core/io
import ../../lib/core/syscall
import ../../lib/core/userdb
import ../../lib/core/passwd
import ../../../lib/fixed_string
import ../../../lib/user_ids
import ./state


const
  HistoryFileName = ".history"
  UserHistoryPath = "/home/rkc/.history"
  HistoryPathMax = U32(PasswdHomeMax) + 16


var historyPathBuf: array[HistoryPathMax, char]


## Clears the temporary buffer used to build the current history file path.
proc clearHistoryPathBuf() =
  var i = U32(0)
  while i < HistoryPathMax:
    historyPathBuf[i] = '\0'
    inc i


## Appends one character to the history path buffer with bounds checking.
proc appendPathChar(pos: var U32, c: char): bool =
  if pos + 1 >= HistoryPathMax:
    return false

  historyPathBuf[pos] = c
  inc pos
  historyPathBuf[pos] = '\0'
  true


## Appends a C string to the history path buffer with bounds checking.
proc appendPathCString(pos: var U32, s: cstring): bool =
  var i = U32(0)
  while s[i] != '\0':
    if not appendPathChar(pos, s[i]):
      return false
    inc i
  true


## Builds the history path for the current uid, falling back to /home/rkc.
proc buildCurrentUserHistoryPath(): cstring =
  clearHistoryPathBuf()

  let uid = sysGetUid()
  if uid == RootUid:
    discard copyCString(historyPathBuf, cstring(HistoryPath))
    return cast[cstring](addr historyPathBuf[0])

  var entry: PasswdEntry

  if not resolveUid(U32(uid), entry):
    discard copyCString(historyPathBuf, cstring(UserHistoryPath))
    return cast[cstring](addr historyPathBuf[0])

  let home = cast[cstring](addr entry.home[0])

  var pos = U32(0)
  if not appendPathCString(pos, home):
    discard copyCString(historyPathBuf, cstring(UserHistoryPath))
    return cast[cstring](addr historyPathBuf[0])

  if pos > 0 and historyPathBuf[pos - 1] != '/':
    discard appendPathChar(pos, '/')

  discard appendPathCString(pos, cstring(HistoryFileName))

  cast[cstring](addr historyPathBuf[0])


## Returns the current visible length of a heap-backed shell input line buffer.
proc lineLen*(buf: ptr UncheckedArray[char], cap: int): int =
  if buf == nil:
    return 0

  var i = 0
  while i < cap:
    if buf[i] == '\0':
      return i
    inc i

  cap - 1


## Serializes in-memory history entries into the save buffer.
proc buildHistorySaveBuf(): U64 =
  var
    outPos: U64 = 0
    h = 0

  while h < historyPos:
    var i = 0
    while i < LineMax:
      let ch = history[h][i]
      if ch == '\0':
        break
      if outPos < HistorySaveBufMax - 1:
        historySaveBuf[outPos] = ch
        inc outPos
      inc i

    if outPos < HistorySaveBufMax - 1:
      historySaveBuf[outPos] = '\n'
      inc outPos

    inc h

  historySaveBuf[outPos] = '\0'
  outPos


## Clears every in-memory shell history entry.
proc clearHistory*() =
  var h = 0
  while h < HistoryMax:
    var i = 0
    while i < LineMax:
      history[h][i] = '\0'
      inc i
    inc h
  historyPos = 0


## Parses the saved history file contents back into history entries.
proc restoreHistoryFromBuf(size: I32) =
  var
    inPos: I32 = 0
    linePos: I32 = 0
    histPos: I32 = 0

  clearHistory()

  while inPos < size and histPos < HistoryMax:
    let ch = historySaveBuf[inPos]
    if ch == '\0':
      break

    if ch == '\n':
      if linePos > 0:
        history[histPos][linePos] = '\0'
        inc histPos
      linePos = 0
    else:
      if linePos < LineMax - 1:
        history[histPos][linePos] = ch
        inc linePos
    inc inPos

  if linePos > 0 and histPos < HistoryMax:
    history[histPos][linePos] = '\0'
    inc histPos
  historyPos = histPos


## Saves the current shell history to the current user's history file.
proc saveHistory*() =
  let
    size = buildHistorySaveBuf()
    path = buildCurrentUserHistoryPath()

  if sysWriteFileMode(path, addr historySaveBuf[0], size, SysFsWriteCreate or SysFsWriteOverwrite) != 0:
    write("failed to write .history\n")


## Loads the current user's history file into memory.
proc loadHistory*() =
  let path = buildCurrentUserHistoryPath()
  let size = sysReadFile(path, addr historySaveBuf[0], U64(HistorySaveBufMax))
  if size > 0:
    restoreHistoryFromBuf(size)


## Prints history entries with a one-based index.
proc printHistory*() =
  var pos = 0
  while pos < historyPos:
    writeUnsigned(U64(pos + 1))
    write("  ")
    write(cstr(history[pos]))
    write("\n")
    inc pos


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