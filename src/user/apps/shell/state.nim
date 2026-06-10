## Holds ORC-managed shell buffers, limits, prompt colors, and buffer helpers.
{.warning[UnusedImport]: off.}

import ../../lib/runtime/orc_osalloc
import ../../lib/core/syscall

const
  LineMax* = 80

  HistoryMax* = 50
  HistorySaveBufMax* = HistoryMax * LineMax
  HistoryPathMax* = 128
  HistoryPath* = "/root/.history"
  CommandScratchBufferCount = 11
  CommandScratchBufferCap* = LineMax
  LineBufferOffset = 0
  CmdBufferOffset = LineBufferOffset + LineMax
  ArgBufferOffset = CmdBufferOffset + LineMax
  PathBufferOffset = ArgBufferOffset + LineMax
  CommandScratchOffset = PathBufferOffset + LineMax
  HistorySaveBufferOffset = CommandScratchOffset +
    CommandScratchBufferCount * CommandScratchBufferCap
  HistoryPathBufferOffset = HistorySaveBufferOffset + HistorySaveBufMax
  ShellManagedStorageSize = HistoryPathBufferOffset + HistoryPathMax

  PromptOrange* = "\x1b[38;5;208m"
  PromptReset* = "\x1b[0m"

var
  shellManagedStorage: seq[char] = @[]
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
  envBuf*: array[SysEnvValueMax, char]

  history*: array[HistoryMax, array[LineMax, char]]
  historyPos*: int32
  historySaveBuf*: ptr UncheckedArray[char] = nil
  historySaveBufCap*: int = 0
  historyPathBuf*: ptr UncheckedArray[char] = nil
  historyPathBufCap*: int = 0


## Allocates the single ORC-owned arena that backs all mutable shell buffers.
proc ensureManagedStorage(): bool =
  if shellManagedStorage.len == ShellManagedStorageSize:
    return true

  shellManagedStorage = newSeq[char](ShellManagedStorageSize)
  shellManagedStorage.len == ShellManagedStorageSize


## Returns a stable pointer view for one range within the managed shell arena.
proc managedBufferAt(offset: int): ptr UncheckedArray[char] =
  if not ensureManagedStorage() or offset < 0 or offset >= ShellManagedStorageSize:
    return nil

  cast[ptr UncheckedArray[char]](addr shellManagedStorage[offset])


## Returns a C string view over a shell line-sized fixed character buffer.
proc cstr*(buf: var array[LineMax, char]): cstring =
  cast[cstring](addr buf[0])


## Returns a C string view over an ORC-managed character buffer.
proc cstr*(buf: ptr UncheckedArray[char]): cstring =
  if buf == nil:
    return nil

  cast[cstring](addr buf[0])


## Initializes the ORC-managed editable shell line buffer.
proc initLineBuffer*(): bool =
  if lineBuf != nil:
    return true

  lineBuf = managedBufferAt(LineBufferOffset)
  if lineBuf == nil:
    lineBufCap = 0
    return false

  lineBufCap = LineMax

  var i = 0
  while i < lineBufCap:
    lineBuf[i] = '\0'
    inc i

  true


## Clears the ORC-managed editable shell line buffer.
proc clearLineBuffer*() =
  if lineBuf == nil:
    return

  var i = 0
  while i < lineBufCap:
    lineBuf[i] = '\0'
    inc i


## Returns the current ORC-managed line buffer as cstring.
proc lineCString*(): cstring =
  cstr(lineBuf)


## Initializes the ORC-managed history save/load buffer.
proc initHistorySaveBuffer*(): bool =
  if historySaveBuf != nil:
    return true

  historySaveBuf = managedBufferAt(HistorySaveBufferOffset)
  if historySaveBuf == nil:
    historySaveBufCap = 0
    return false

  historySaveBufCap = HistorySaveBufMax

  var i = 0
  while i < historySaveBufCap:
    historySaveBuf[i] = '\0'
    inc i

  true


## Clears the ORC-managed history save/load buffer.
proc clearHistorySaveBuffer*() =
  if historySaveBuf == nil:
    return

  var i = 0
  while i < historySaveBufCap:
    historySaveBuf[i] = '\0'
    inc i


## Returns the ORC-managed history save/load buffer as cstring.
proc historySaveCString*(): cstring =
  cstr(historySaveBuf)


## Initializes the ORC-managed history path buffer.
proc initHistoryPathBuffer*(): bool =
  if historyPathBuf != nil:
    return true

  historyPathBuf = managedBufferAt(HistoryPathBufferOffset)
  if historyPathBuf == nil:
    historyPathBufCap = 0
    return false

  historyPathBufCap = HistoryPathMax

  var i = 0
  while i < historyPathBufCap:
    historyPathBuf[i] = '\0'
    inc i
  
  true


## Clears the ORC-managed history path buffer.
proc clearHistoryPathBuffer*() =
  if historyPathBuf == nil:
    return

  var i = 0
  while i < historyPathBufCap:
    historyPathBuf[i] = '\0'
    inc i


## Returns the ORC-managed history path buffer as cstring.
proc historyPathCString*(): cstring =
  cstr(historyPathBuf)


## Initializes the ORC-managed command buffer.
proc initCmdBuffer*(): bool =
  if cmdBuf != nil:
    return true

  cmdBuf = managedBufferAt(CmdBufferOffset)
  if cmdBuf == nil:
    cmdBufCap = 0
    return false

  cmdBufCap = LineMax

  var i = 0
  while i < cmdBufCap:
    cmdBuf[i] = '\0'
    inc i
  
  true


## Clears the ORC-managed command line buffer.
proc clearCmdBuffer*() =
  if cmdBuf == nil:
    return

  var i = 0
  while i < cmdBufCap:
    cmdBuf[i] = '\0'
    inc i


## Returns the ORC-managed command line buffer as cstring.
proc cmdCString*(): cstring =
  cstr(cmdBuf)


## Initializes the ORC-managed argument buffer.
proc initArgBuffer*(): bool =
  if argBuf != nil:
    return true

  argBuf = managedBufferAt(ArgBufferOffset)
  if argBuf == nil:
    argBufCap = 0
    return false

  argBufCap = LineMax

  var i = 0
  while i < argBufCap:
    argBuf[i] = '\0'
    inc i

  true


## Clears the ORC-managed argument buffer.
proc clearArgBuffer*() =
  if argBuf == nil:
    return

  var i = 0
  while i < argBufCap:
    argBuf[i] = '\0'
    inc i


## Returns the ORC-managed argument buffer as cstring.
proc argCString*(): cstring =
  cstr(argBuf)


## Initializes ORC-managed scratch buffers used by pipe and redirection parsing.
proc initCommandScratchBuffers*(): bool =
  if commandScratchArena != nil:
    return true

  let bytes = CommandScratchBufferCount * CommandScratchBufferCap
  commandScratchArena = managedBufferAt(CommandScratchOffset)
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


## Clears the fixed argument handoff buffer used for child execution.
proc clearExecArgBuffer*() =
  var i = 0
  while i < LineMax:
    execArgBuf[i] = '\0'
    inc i


## Copies parsed arguments into the stable buffer handed to a child process.
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


## Initializes the ORC-managed executable path buffer.
proc initPathBuffer*(): bool =
  if pathBuf != nil:
    return true

  pathBuf = managedBufferAt(PathBufferOffset)
  if pathBuf == nil:
    pathBufCap = 0
    return false

  pathBufCap = LineMax

  var i = 0
  while i < pathBufCap:
    pathBuf[i] = '\0'
    inc i

  true


## Clears the ORC-managed executable path buffer.
proc clearPathBuffer*() =
  if pathBuf == nil:
    return

  var i = 0
  while i < pathBufCap:
    pathBuf[i] = '\0'
    inc i


## Returns the ORC-managed executable path buffer as cstring.
proc pathCString*(): cstring =
  cstr(pathBuf)
