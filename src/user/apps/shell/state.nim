import ../../lib/core/syscall

const
  LineMax* = 80

  HistoryMax* = 50
  HistorySaveBufMax* = HistoryMax * LineMax
  HistoryPath* = "/.history"

  PromptOrange* = "\x1b[38;5;208m"
  PromptReset* = "\x1b[0m"

var
  lineBuf*: array[LineMax, char]
  cmdBuf*: array[LineMax, char]
  argBuf*: array[LineMax, char]
  pathBuf*: array[LineMax, char]
  cwdBuf*: array[SysProcessCwdMax, char]

  history*: array[HistoryMax, array[LineMax, char]]
  historyPos*: int32
  historySaveBuf*: array[HistorySaveBufMax, char]


proc cstr*(buf: var array[LineMax, char]): cstring =
  cast[cstring](addr buf[0])
