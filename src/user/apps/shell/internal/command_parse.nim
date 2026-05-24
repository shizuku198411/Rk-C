## Parses command names, arguments, background markers, and executable paths.

## Clears a line-sized shell buffer.
proc clearBuffer(buf: ptr UncheckedArray[char]) =
  clearCommandScratchBuffer(buf)


## Advances a parser cursor over ASCII spaces.
proc skipSpaces(s: cstring, pos: var int) =
  while s[pos] == ' ':
    inc pos


## Splits a command line into command and raw argument buffers.
proc parseCommandInto(line: cstring, cmd, arg: ptr UncheckedArray[char]): bool =
  if line == nil or cmd == nil or arg == nil:
    return false

  clearBuffer(cmd)
  clearBuffer(arg)

  var pos = 0
  skipSpaces(line, pos)

  var i = U64(0)
  while line[pos] != '\0' and line[pos] != ' ' and i < CommandScratchBufferCap - 1:
    cmd[i] = line[pos]
    inc i
    inc pos
  cmd[i] = '\0'
  if i == 0:
    return false

  skipSpaces(line, pos)
  i = 0
  while line[pos] != '\0' and i < CommandScratchBufferCap - 1:
    arg[i] = line[pos]
    inc i
    inc pos
  arg[i] = '\0'
  true


## Parses the active shell line into the shared command and argument buffers.
proc parseCommand*(line: cstring): bool =
  if line == nil:
    return false

  if cmdBuf == nil or argBuf == nil:
    return false

  clearCmdBuffer()
  clearArgBuffer()

  var i = 0

  while line[i] == ' ':
    inc i

  if line[i] == '\0':
    return false

  var cmdPos = 0
  while line[i] != '\0' and line[i] != ' ':
    if cmdPos + 1 < cmdBufCap:
      cmdBuf[cmdPos] = line[i]
      inc cmdPos
    inc i

  cmdBuf[cmdPos] = '\0'

  if cmdPos == 0:
    return false

  while line[i] == ' ':
    inc i

  var argPos = 0
  while line[i] != '\0':
    if argPos + 1 < argBufCap:
      argBuf[argPos] = line[i]
      inc argPos
    inc i

  argBuf[argPos] = '\0'

  true


## Removes a trailing background marker from an argument buffer.
proc stripBackgroundMarkerFrom(buf: ptr UncheckedArray[char]): bool =
  if buf == nil:
    return false

  var len = U64(0)
  while len < CommandScratchBufferCap and buf[len] != '\0':
    inc len

  while len > 0 and buf[len - 1] == ' ':
    dec len
    buf[len] = '\0'

  if len == 0 or buf[len - 1] != '&':
    return false

  dec len
  buf[len] = '\0'
  while len > 0 and buf[len - 1] == ' ':
    dec len
    buf[len] = '\0'

  true


