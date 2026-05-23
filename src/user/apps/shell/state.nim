## Holds shared shell buffers, limits, prompt colors, and buffer helpers.
import ../../lib/core/heap
import ../../lib/core/syscall

const
  LineMax* = 80

  HistoryMax* = 50
  HistorySaveBufMax* = HistoryMax * LineMax
  HistoryPathMax* = 128
  HistoryPath* = "/.history"
  CommandScratchBufferCount = 11
  CommandScratchBufferCap* = LineMax

  PromptOrange* = "\x1b[38;5;208m"
  PromptReset* = "\x1b[0m"

var
  lineBuf*: ptr UncheckedArray[char] = nil
  lineBufCap*: int = 0

  cmdBuf*: ptr UncheckedArray[char] = nil
  cmdBufCap*: int = 0

  argBuf*: ptr UncheckedArray[char] = nil
  argBufCap*: int = 0
  execArgBuf*: array[LineMax, char]

  pathBuf*: ptr UncheckedArray[char] = nil
  pathBufCap*: int = 0

  commandScratchArena: ptr UncheckedArray[char] = nil
  pipelineLineBuf*: ptr UncheckedArray[char] = nil
  redirectLineBuf*: ptr UncheckedArray[char] = nil
  leftLineBuf*: ptr UncheckedArray[char] = nil
  rightLineBuf*: ptr UncheckedArray[char] = nil
  redirectTargetBuf*: ptr UncheckedArray[char] = nil
  leftCmdBuf*: ptr UncheckedArray[char] = nil
  leftArgBuf*: ptr UncheckedArray[char] = nil
  leftPathBuf*: ptr UncheckedArray[char] = nil
  rightCmdBuf*: ptr UncheckedArray[char] = nil
  rightArgBuf*: ptr UncheckedArray[char] = nil
  rightPathBuf*: ptr UncheckedArray[char] = nil

  cwdBuf*: array[SysProcessCwdMax, char]

  history*: array[HistoryMax, array[LineMax, char]]
  historyPos*: int32
  historySaveBuf*: ptr UncheckedArray[char] = nil
  historySaveBufCap*: int = 0
  historyPathBuf*: ptr UncheckedArray[char] = nil
  historyPathBufCap*: int = 0


## Returns a C string view over a shell line-sized fixed character buffer.
proc cstr*(buf: var array[LineMax, char]): cstring =
  cast[cstring](addr buf[0])


## Returns a C string view over a heap-backed character buffer.
proc cstr*(buf: ptr UncheckedArray[char]): cstring =
  if buf == nil:
    return nil

  cast[cstring](addr buf[0])


## Initializes the heap-backed editable shell line buffer.
proc initLineBuffer*(): bool =
  if lineBuf != nil:
    return true

  lineBuf = cast[ptr UncheckedArray[char]](userAlloc(LineMax))
  if lineBuf == nil:
    lineBufCap = 0
    return false

  lineBufCap = LineMax

  var i = 0
  while i < lineBufCap:
    lineBuf[i] = '\0'
    inc i

  true


## Clears the heap-backed editable shell line buffer.
proc clearLineBuffer*() =
  if lineBuf == nil:
    return

  var i = 0
  while i < lineBufCap:
    lineBuf[i] = '\0'
    inc i


## Returns the current heap-backed line buffer as cstring.
proc lineCString*(): cstring =
  cstr(lineBuf)


## Initializes the heap-backed history save/load buffer.
proc initHistorySaveBuffer*(): bool =
  if historySaveBuf != nil:
    return true

  historySaveBuf = cast[ptr UncheckedArray[char]](userAlloc(HistorySaveBufMax))
  if historySaveBuf == nil:
    historySaveBufCap = 0
    return false

  historySaveBufCap = HistorySaveBufMax

  var i = 0
  while i < historySaveBufCap:
    historySaveBuf[i] = '\0'
    inc i

  true


## Clears the heap-backed history save/load buffer.
proc clearHistorySaveBuffer*() =
  if historySaveBuf == nil:
    return

  var i = 0
  while i < historySaveBufCap:
    historySaveBuf[i] = '\0'
    inc i


## Returns the heap-backed history save/load buffer as cstring.
proc historySaveCString*(): cstring =
  cstr(historySaveBuf)


## Initializes the heap-backed history path buffer.
proc initHistoryPathBuffer*(): bool =
  if historyPathBuf != nil:
    return true

  historyPathBuf = cast[ptr UncheckedArray[char]](userAlloc(HistoryPathMax))
  if historyPathBuf == nil:
    historyPathBufCap = 0
    return false

  historyPathBufCap = HistoryPathMax

  var i = 0
  while i < historyPathBufCap:
    historyPathBuf[i] = '\0'
    inc i
  
  true


## Clears the heap-backed history path buffer.
proc clearHistoryPathBuffer*() =
  if historyPathBuf == nil:
    return

  var i = 0
  while i < historyPathBufCap:
    historyPathBuf[i] = '\0'
    inc i


## Returns the heap-backed history path buffer as cstring.
proc historyPathCString*(): cstring =
  cstr(historyPathBuf)


## Initializes the heap-backed 1 buffer.
proc initCmdBuffer*(): bool =
  if cmdBuf != nil:
    return true

  cmdBuf = cast[ptr UncheckedArray[char]](userAlloc(LineMax))
  if cmdBuf == nil:
    cmdBufCap = 0
    return false

  cmdBufCap = LineMax

  var i = 0
  while i < cmdBufCap:
    cmdBuf[i] = '\0'
    inc i
  
  true


## Clears the heap-backed command line buffer.
proc clearCmdBuffer*() =
  if cmdBuf == nil:
    return

  var i = 0
  while i < cmdBufCap:
    cmdBuf[i] = '\0'
    inc i


## Returns the heap-backed command line buffer as cstring.
proc cmdCString*(): cstring =
  cstr(cmdBuf)


## Initializes the heap-backed arg buffer.
proc initArgBuffer*(): bool =
  if argBuf != nil:
    return true

  argBuf = cast[ptr UncheckedArray[char]](userAlloc(LineMax))
  if argBuf == nil:
    argBufCap = 0
    return false

  argBufCap = LineMax

  var i = 0
  while i < argBufCap:
    argBuf[i] = '\0'
    inc i

  true


## Clears the heap-backed arg buffer.
proc clearArgBuffer*() =
  if argBuf == nil:
    return

  var i = 0
  while i < argBufCap:
    argBuf[i] = '\0'
    inc i


## Returns the heap-backed arg buffer as cstring.
proc argCString*(): cstring =
  cstr(argBuf)


## Initializes heap-backed scratch buffers used by pipe and redirection parsing.
proc initCommandScratchBuffers*(): bool =
  if commandScratchArena != nil:
    return true

  let bytes = CommandScratchBufferCount * CommandScratchBufferCap
  commandScratchArena = cast[ptr UncheckedArray[char]](userAlloc(U64(bytes)))
  if commandScratchArena == nil:
    return false

  template bufferAt(index: int): ptr UncheckedArray[char] =
    cast[ptr UncheckedArray[char]](
      cast[U64](commandScratchArena) + U64(index * CommandScratchBufferCap)
    )

  pipelineLineBuf = bufferAt(0)
  redirectLineBuf = bufferAt(1)
  leftLineBuf = bufferAt(2)
  rightLineBuf = bufferAt(3)
  redirectTargetBuf = bufferAt(4)
  leftCmdBuf = bufferAt(5)
  leftArgBuf = bufferAt(6)
  leftPathBuf = bufferAt(7)
  rightCmdBuf = bufferAt(8)
  rightArgBuf = bufferAt(9)
  rightPathBuf = bufferAt(10)

  var i = 0
  while i < bytes:
    commandScratchArena[i] = '\0'
    inc i

  true


## Clears one pipe or redirection command scratch buffer.
proc clearCommandScratchBuffer*(buf: ptr UncheckedArray[char]) =
  if buf == nil:
    return

  var i = 0
  while i < CommandScratchBufferCap:
    buf[i] = '\0'
    inc i


proc clearExecArgBuffer*() =
  var i = 0
  while i < LineMax:
    execArgBuf[i] = '\0'
    inc i


proc copyArgToExecArgBuffer*(): cstring =
  clearExecArgBuffer()

  if argBuf == nil:
    return nil

  if argBuf[0] == '\0':
    return nil

  var i = 0
  while i + 1 < LineMax and i < argBufCap and argBuf[i] != '\0':
    execArgBuf[i] = argBuf[i]
    inc i

  execArgBuf[i] = '\0'

  cast[cstring](addr execArgBuf[0])


proc initPathBuffer*(): bool =
  if pathBuf != nil:
    return true

  pathBuf = cast[ptr UncheckedArray[char]](userAlloc(LineMax))
  if pathBuf == nil:
    pathBufCap = 0
    return false

  pathBufCap = LineMax

  var i = 0
  while i < pathBufCap:
    pathBuf[i] = '\0'
    inc i

  true


proc clearPathBuffer*() =
  if pathBuf == nil:
    return

  var i = 0
  while i < pathBufCap:
    pathBuf[i] = '\0'
    inc i


proc pathCString*(): cstring =
  cstr(pathBuf)
