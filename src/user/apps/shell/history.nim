import ../../lib/core/io
import ../../lib/core/syscall
import ./state


proc lineLen*(buf: var array[LineMax, char]): int =
  var i = 0
  while i < LineMax:
    if buf[i] == '\0':
      return i
    inc i
  LineMax - 1


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


proc clearHistory() =
  var h = 0
  while h < HistoryMax:
    var i = 0
    while i < LineMax:
      history[h][i] = '\0'
      inc i
    inc h
  historyPos = 0


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


proc saveHistory*() =
  let size = buildHistorySaveBuf()

  if sysWriteFile(cstring(HistoryPath), addr historySaveBuf[0], size) != 0:
    write("failed to write .history\n")


proc loadHistory*() =
  let size = sysReadFile(cstring(HistoryPath), addr historySaveBuf[0], U64(HistorySaveBufMax))
  if size > 0:
    restoreHistoryFromBuf(size)


proc printHistory*() =
  var pos = 0
  while pos < historyPos:
    writeUnsigned(U64(pos + 1))
    write("  ")
    write(cstr(history[pos]))
    write("\n")
    inc pos


proc storeHistory*() =
  if historyPos < int32(HistoryMax):
    copyMem(addr history[historyPos][0], addr lineBuf[0], LineMax)
    inc historyPos
  else:
    var i = 1
    while i < HistoryMax:
      copyMem(addr history[i - 1][0], addr history[i][0], LineMax)
      inc i
    copyMem(addr history[HistoryMax - 1][0], addr lineBuf[0], LineMax)
