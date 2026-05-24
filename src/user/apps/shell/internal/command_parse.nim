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


## Builds a /bin/<command> executable path into the requested buffer.
proc buildBinPathInto(cmd: cstring, dst: ptr UncheckedArray[char]): cstring =
  if cmd == nil or dst == nil:
    return nil

  clearBuffer(dst)
  dst[0] = '/'
  dst[1] = 'b'
  dst[2] = 'i'
  dst[3] = 'n'
  dst[4] = '/'
  var i = U64(0)
  while cmd[i] != '\0' and i + 5 < CommandScratchBufferCap - 1:
    dst[i + 5] = cmd[i]
    inc i

  if cmd[i] != '\0':
    return nil

  dst[i + 5] = '\0'
  cast[cstring](addr dst[0])


## Builds a /bin/<command> executable path into the shared path buffer.
proc buildBinPath*(cmd: cstring): cstring =
  if cmd == nil:
    return nil

  if not initPathBuffer():
    return nil

  clearPathBuffer()

  var pos = 0

  if cmd[0] == '/':
    while cmd[pos] != '\0' and pos + 1 < pathBufCap:
      pathBuf[pos] = cmd[pos]
      inc pos

    if cmd[pos] != '\0':
      return nil

    pathBuf[pos] = '\0'
    return pathCString()

  let prefix = cstring"/bin/"
  var i = 0

  while prefix[i] != '\0' and pos + 1 < pathBufCap:
    pathBuf[pos] = prefix[i]
    inc pos
    inc i

  i = 0
  while cmd[i] != '\0' and pos + 1 < pathBufCap:
    pathBuf[pos] = cmd[i]
    inc pos
    inc i

  if cmd[i] != '\0':
    return nil

  pathBuf[pos] = '\0'
  pathCString()


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


proc buildBinPathIntoHeap*(
  cmd: cstring,
  outBuf: ptr UncheckedArray[char],
  outCap: int
): cstring =
  if outBuf == nil or outCap <= 0:
    return nil

  var i = 0
  while i < outCap:
    outBuf[i] = '\0'
    inc i

  if cmd == nil:
    return cast[cstring](addr outBuf[0])

  var pos = 0

  if cmd[0] == '/':
    i = 0
    while cmd[i] != '\0' and pos + 1 < outCap:
      outBuf[pos] = cmd[i]
      inc pos
      inc i

    if cmd[i] != '\0':
      return nil

    outBuf[pos] = '\0'
    return cast[cstring](addr outBuf[0])

  let prefix = cstring"/bin/"
  i = 0
  while prefix[i] != '\0' and pos + 1 < outCap:
    outBuf[pos] = prefix[i]
    inc pos
    inc i

  i = 0
  while cmd[i] != '\0' and pos + 1 < outCap:
    outBuf[pos] = cmd[i]
    inc pos
    inc i

  if cmd[i] != '\0':
    return nil

  outBuf[pos] = '\0'
  cast[cstring](addr outBuf[0])


