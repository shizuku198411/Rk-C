## Holds shared shell buffers, limits, prompt colors, and buffer helpers.
import ../../lib/core/heap
import ../../lib/core/syscall
import ../../../lib/types

const
  LineMax* = 80

  HistoryMax* = 50
  HistorySaveBufMax* = HistoryMax * LineMax
  HistoryPath* = "/.history"

  PromptOrange* = "\x1b[38;5;208m"
  PromptReset* = "\x1b[0m"

var
  lineBuf*: ptr UncheckedArray[char] = nil
  lineBufCap*: int = 0

  cmdBuf*: array[LineMax, char]
  argBuf*: array[LineMax, char]
  pathBuf*: array[LineMax, char]
  cwdBuf*: array[SysProcessCwdMax, char]

  history*: array[HistoryMax, array[LineMax, char]]
  historyPos*: int32
  historySaveBuf*: array[HistorySaveBufMax, char]


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