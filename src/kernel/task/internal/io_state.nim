## Implements process file-descriptor state and in-kernel pipe storage.

## Implements the pipe next kernel helper.
proc pipeNext(index: U32): U32 =
  (index + 1) mod SysPipeBufSize


## Returns whether pipe id is valid.
proc validPipeId(pipeId: I32): bool =
  pipeId >= 0 and pipeId < I32(SysPipeMax) and pipes[U32(pipeId)].used


## Allocates pipe.
proc allocPipe*(): I32 =
  var i = U32(0)
  while i < SysPipeMax:
    if not pipes[i].used:
      pipes[i] = PipeState()
      pipes[i].used = true
      pipes[i].readers = 1
      pipes[i].writers = 1
      return I32(i)

    inc i

  -1


## Frees pipe.
proc freePipe*(pipeId: I32) =
  if validPipeId(pipeId):
    pipes[U32(pipeId)] = PipeState()


## Retains fd entry.
proc retainFdEntry*(entry: FdEntry) =
  if entry.used and entry.kind == SysFdKindPipe and validPipeId(entry.pipeId):
    if (entry.flags and SysOpenRead) != 0:
      inc pipes[U32(entry.pipeId)].readers
    if (entry.flags and SysOpenWrite) != 0:
      inc pipes[U32(entry.pipeId)].writers


## Releases fd entry.
proc releaseFdEntry*(entry: FdEntry) =
  if not entry.used or entry.kind != SysFdKindPipe or not validPipeId(entry.pipeId):
    return

  let pipe = addr pipes[U32(entry.pipeId)]
  if (entry.flags and SysOpenRead) != 0 and pipe.readers > 0:
    dec pipe.readers
    wakePipeWriters(entry.pipeId)
  if (entry.flags and SysOpenWrite) != 0 and pipe.writers > 0:
    dec pipe.writers
    wakePipeReaders(entry.pipeId)

  if pipe.readers == 0 and pipe.writers == 0:
    pipe[] = PipeState()


## Implements the pipe read kernel kernel helper.
proc pipeReadKernel*(pipeId: I32, dst: ptr UncheckedArray[U8], len: U64): I32 =
  if dst == nil or not validPipeId(pipeId):
    return -1

  let pipe = addr pipes[U32(pipeId)]
  var readLen = U64(0)
  while readLen < len:
    while pipe.count == 0:
      if pipe.writers == 0:
        return I32(readLen)
      sleepCurrentForPipeRead(pipeId)
      if not validPipeId(pipeId):
        return -1

    dst[readLen] = pipe.data[pipe.head]
    pipe.head = pipeNext(pipe.head)
    dec pipe.count
    inc readLen
    wakePipeWriters(pipeId)

  I32(readLen)


## Implements the pipe write kernel kernel helper.
proc pipeWriteKernel*(pipeId: I32, src: ptr UncheckedArray[U8], len: U64): I32 =
  if src == nil or not validPipeId(pipeId):
    return -1

  let pipe = addr pipes[U32(pipeId)]
  var written = U64(0)
  while written < len:
    if pipe.readers == 0:
      return -1

    while pipe.count == SysPipeBufSize:
      if pipe.readers == 0:
        return -1
      sleepCurrentForPipeWrite(pipeId)
      if not validPipeId(pipeId):
        return -1

    pipe.data[pipe.tail] = src[written]
    pipe.tail = pipeNext(pipe.tail)
    inc pipe.count
    inc written
    wakePipeReaders(pipeId)

  I32(written)


## Implements the pipe readable kernel helper.
proc pipeReadable*(pipeId: I32): bool =
  if not validPipeId(pipeId):
    return false

  let pipe = addr pipes[U32(pipeId)]
  pipe.count > 0 or pipe.writers == 0


## Implements the pipe writable kernel helper.
proc pipeWritable*(pipeId: I32): bool =
  if not validPipeId(pipeId):
    return false

  let pipe = addr pipes[U32(pipeId)]
  pipe.readers > 0 and pipe.count < SysPipeBufSize


## Clears file state.
proc clearFileState*(p: ptr Process) =
  var i = U32(0)
  while i < SysFdMax:
    releaseFdEntry(p.files.entries[i])
    inc i

  p.files = FileState()


## Sets fd path.
proc setFdPath(entry: var FdEntry, path: cstring) =
  var i = U32(0)
  while i < SysFdPathMax - 1 and path != nil and path[i] != '\0':
    entry.path[i] = path[i]
    inc i

  while i < SysFdPathMax:
    entry.path[i] = '\0'
    inc i


## Initializes standard files.
proc initStandardFiles*(p: ptr Process) =
  clearFileState(p)

  p.files.entries[0].used = true
  p.files.entries[0].kind = SysFdKindTty
  p.files.entries[0].flags = SysOpenRead
  p.files.entries[0].ttyId = Tty0Id
  setFdPath(p.files.entries[0], "/dev/stdin")

  p.files.entries[1].used = true
  p.files.entries[1].kind = SysFdKindTty
  p.files.entries[1].flags = SysOpenWrite
  p.files.entries[1].ttyId = Tty0Id
  setFdPath(p.files.entries[1], "/dev/stdout")

  p.files.entries[2].used = true
  p.files.entries[2].kind = SysFdKindTty
  p.files.entries[2].flags = SysOpenWrite
  p.files.entries[2].ttyId = Tty0Id
  setFdPath(p.files.entries[2], "/dev/stderr")


## Copies file state.
proc copyFileState(dst, src: ptr Process) =
  dst.files = src.files
  var i = U32(0)
  while i < SysFdMax:
    retainFdEntry(dst.files.entries[i])
    inc i

