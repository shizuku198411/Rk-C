## Handles open file descriptors, pipes, duplicate descriptors, and seek.

## Implements the refresh fd size kernel helper.
proc refreshFdSize(entry: var FdEntry): bool =
  let size = serviceFileSizeToKernel(fdPath(entry))
  if size < 0:
    return false

  entry.size = U64(size)
  true


## Handles the open syscall operation.
proc syscallOpen*(pathVal, flagsVal: U64): U64 =
  let path = readPath(pathVal)
  if path == nil or currentProc == nil:
    return U64(-1'i64)

  let fd = allocFd()
  if fd < 0:
    return U64(-1'i64)

  let flags = U32(flagsVal)
  if (flags and (SysOpenRead or SysOpenWrite)) == 0:
    return U64(-1'i64)

  var entry = FdEntry()
  entry.used = true
  entry.flags = flags
  entry.kind = deviceKindForPath(path)
  copyFdPath(entry, path)

  if entry.kind != SysFdKindFile:
    if entry.kind == SysFdKindStdin and (flags and SysOpenWrite) != 0:
      return U64(-1'i64)
    if (entry.kind == SysFdKindStdout or entry.kind == SysFdKindStderr) and
        (flags and SysOpenRead) != 0:
      return U64(-1'i64)
    if not canOpenDevicePath(path, flags):
      return U64(-1'i64)

    currentProc.files.entries[U32(fd)] = entry
    return U64(fd)

  if not canOpenFilePath(path, flags):
    return U64(-1'i64)

  if (flags and (SysOpenCreate or SysOpenTrunc)) != 0:
    if serviceWriteFile(fdPath(entry), addr fdFileBuf[0], 0) != 0:
      return U64(-1'i64)

  if not refreshFdSize(entry):
    return U64(-1'i64)

  if (flags and SysOpenAppend) != 0:
    entry.offset = entry.size

  currentProc.files.entries[U32(fd)] = entry
  U64(fd)


## Handles the read fd syscall operation.
proc syscallReadFd*(fdVal, bufVal, len: U64): U64 =
  if bufVal == 0 or len > SysFileIoMax or not validFd(I32(fdVal)):
    return U64(-1'i64)

  var entry = addr currentProc.files.entries[U32(fdVal)]
  if (entry.flags and SysOpenRead) == 0:
    return U64(-1'i64)

  if entry.kind == SysFdKindStdin or entry.kind == SysFdKindConsole:
    return syscallConsoleRead(bufVal, len)
  if entry.kind == SysFdKindPipe:
    let readLen = pipeReadKernel(entry.pipeId, cast[ptr UncheckedArray[U8]](addr fdFileBuf[0]), len)
    if readLen < 0:
      return U64(-1'i64)
    if readLen == 0:
      return 0
    if copyToUser(bufVal, addr fdFileBuf[0], U64(readLen)) != 0:
      return U64(-1'i64)

    return U64(readLen)
  if entry.kind != SysFdKindFile:
    return U64(-1'i64)
  if not canReadPath(fdPath(entry[])):
    return U64(-1'i64)

  if not refreshFdSize(entry[]):
    return U64(-1'i64)

  if entry.offset >= entry.size:
    return 0

  let remain = entry.size - entry.offset
  let readLen =
    if len > remain:
      remain
    else:
      len

  let actualLen = serviceReadFileRangeToKernel(fdPath(entry[]), addr fdFileBuf[0], entry.offset, readLen)
  if actualLen < 0:
    return U64(-1'i64)
  if actualLen == 0:
    return 0

  if copyToUser(bufVal, addr fdFileBuf[0], U64(actualLen)) != 0:
    return U64(-1'i64)

  entry.offset += U64(actualLen)
  U64(actualLen)


## Handles the write fd syscall operation.
proc syscallWriteFd*(fdVal, bufVal, len: U64): U64 =
  if len > SysFileIoMax or not validFd(I32(fdVal)):
    return U64(-1'i64)

  var entry = addr currentProc.files.entries[U32(fdVal)]
  if (entry.flags and SysOpenWrite) == 0:
    return U64(-1'i64)

  if entry.kind == SysFdKindStdout or entry.kind == SysFdKindStderr or
      entry.kind == SysFdKindConsole:
    return syscallConsoleWrite(bufVal, len)
  if entry.kind == SysFdKindPipe:
    if copyFromUser(addr fdFileBuf[0], bufVal, len) != 0:
      return U64(-1'i64)

    let written = pipeWriteKernel(entry.pipeId, cast[ptr UncheckedArray[U8]](addr fdFileBuf[0]), len)
    if written < 0:
      return U64(-1'i64)

    return U64(written)
  if entry.kind != SysFdKindFile:
    return U64(-1'i64)
  if not canWritePath(fdPath(entry[])):
    return U64(-1'i64)

  if copyFromUser(addr fdFileBuf[0], bufVal, len) != 0:
    return U64(-1'i64)

  let rc = serviceWriteFileRange(fdPath(entry[]), addr fdFileBuf[0], entry.offset, len)
  if I32(rc) != 0:
    return U64(-1'i64)

  entry.offset += len
  if entry.offset > entry.size:
    entry.size = entry.offset
  len


## Handles the close syscall operation.
proc syscallClose*(fdVal: U64): U64 =
  if not validFd(I32(fdVal)):
    return U64(-1'i64)

  releaseFdEntry(currentProc.files.entries[U32(fdVal)])
  currentProc.files.entries[U32(fdVal)] = FdEntry()
  0


## Handles the pipe syscall operation.
proc syscallPipe*(fdsVal: U64): U64 =
  if currentProc == nil or fdsVal == 0:
    return U64(-1'i64)

  let readFd = findFreeFd()
  if readFd < 0:
    return U64(-1'i64)

  let writeFd = findFreeFd(readFd)
  if writeFd < 0:
    return U64(-1'i64)

  let pipeId = allocPipe()
  if pipeId < 0:
    return U64(-1'i64)

  var fds: array[2, I32]
  fds[0] = readFd
  fds[1] = writeFd
  if copyToUser(fdsVal, addr fds[0], U64(sizeof(fds))) != 0:
    freePipe(pipeId)
    return U64(-1'i64)

  var readEntry = FdEntry()
  readEntry.used = true
  readEntry.kind = SysFdKindPipe
  readEntry.flags = SysOpenRead
  readEntry.pipeId = pipeId
  copyFdPath(readEntry, "/dev/pipe")

  var writeEntry = FdEntry()
  writeEntry.used = true
  writeEntry.kind = SysFdKindPipe
  writeEntry.flags = SysOpenWrite
  writeEntry.pipeId = pipeId
  copyFdPath(writeEntry, "/dev/pipe")

  currentProc.files.entries[U32(readFd)] = readEntry
  currentProc.files.entries[U32(writeFd)] = writeEntry
  0


## Handles the dup2 syscall operation.
proc syscallDup2*(oldFdVal, newFdVal: U64): U64 =
  let oldFd = I32(oldFdVal)
  let newFd = I32(newFdVal)
  if not validFd(oldFd) or newFd < 0 or newFd >= I32(SysFdMax):
    return U64(-1'i64)

  if oldFd == newFd:
    return U64(newFd)

  if currentProc.files.entries[U32(newFd)].used:
    releaseFdEntry(currentProc.files.entries[U32(newFd)])

  currentProc.files.entries[U32(newFd)] = currentProc.files.entries[U32(oldFd)]
  retainFdEntry(currentProc.files.entries[U32(newFd)])
  U64(newFd)


## Handles the lseek syscall operation.
proc syscallLseek*(fdVal, offsetVal, whence: U64): U64 =
  if not validFd(I32(fdVal)):
    return U64(-1'i64)

  var entry = addr currentProc.files.entries[U32(fdVal)]
  if entry.kind != SysFdKindFile:
    entry.offset = 0
    return 0

  discard refreshFdSize(entry[])

  let offset = I64(offsetVal)
  let base =
    if whence == SysSeekSet:
      I64(0)
    elif whence == SysSeekCur:
      I64(entry.offset)
    elif whence == SysSeekEnd:
      I64(entry.size)
    else:
      return U64(-1'i64)

  let next = base + offset
  if next < 0:
    return U64(-1'i64)

  entry.offset = U64(next)
  entry.offset

