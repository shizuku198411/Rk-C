import ../../../lib/types
import ../../../lib/syscall_types
import ../../syscall/fs/fs_service_ops
import ../../syscall/io/console_io
import ../../mm/usercopy
import ../../task/process

const
  SysPathMax = U64(128)
  SysDirEntryMax = U64(32)
  SysFileIoMax = U64(4096)

var
  pathBuf: array[SysPathMax, char]
  fileBuf: array[SysFileIoMax, U8]
  fdFileBuf: array[SysFileIoMax, U8]


proc readPath(pathVal: U64, defaultRoot: bool = false): cstring =
  if pathVal == 0:
    if defaultRoot:
      return "/"
    return nil

  if copyUserCString(addr pathBuf[0], pathVal, SysPathMax) < 0:
    return nil

  cast[cstring](addr pathBuf[0])


proc syscallLs*(pathVal, entriesVal, maxEntries: U64): U64 =
  if entriesVal == 0 or maxEntries == 0:
    return U64(-1'i64)

  let path = readPath(pathVal, true)
  if path == nil:
    return U64(-1'i64)

  let countMax =
    if maxEntries > SysDirEntryMax:
      SysDirEntryMax
    else:
      maxEntries
  serviceLs(path, entriesVal, countMax)


proc syscallMkdir*(path: U64): U64 =
  let copiedPath = readPath(path)
  if copiedPath == nil:
    return U64(-1'i64)

  serviceMkdir(copiedPath)


proc syscallUnlink*(path: U64): U64 =
  let copiedPath = readPath(path)
  if copiedPath == nil:
    return U64(-1'i64)

  serviceUnlink(copiedPath)


proc syscallRmdir*(path: U64): U64 =
  let copiedPath = readPath(path)
  if copiedPath == nil:
    return U64(-1'i64)

  serviceRmdir(copiedPath)


proc syscallReadFile*(path, buf, capacity: U64): U64 =
  if buf == 0 or capacity > SysFileIoMax:
    return U64(-1'i64)

  let copiedPath = readPath(path)
  if copiedPath == nil:
    return U64(-1'i64)

  serviceReadFile(copiedPath, buf, capacity)


proc syscallWriteFile*(path, buf, size: U64): U64 =
  if size > SysFileIoMax:
    return U64(-1'i64)

  let copiedPath = readPath(path)
  if copiedPath == nil:
    return U64(-1'i64)
  if copyFromUser(addr fileBuf[0], buf, size) != 0:
    return U64(-1'i64)

  serviceWriteFile(copiedPath, addr fileBuf[0], size)


proc copyFdPath(entry: var FdEntry, path: cstring) =
  var i = U32(0)
  while i < SysFdPathMax - 1 and path[i] != '\0':
    entry.path[i] = path[i]
    inc i

  while i < SysFdPathMax:
    entry.path[i] = '\0'
    inc i


proc fdPath(entry: var FdEntry): cstring =
  cast[cstring](addr entry.path[0])


proc pathEq(a, b: cstring): bool =
  if a == nil or b == nil:
    return false

  var i = 0
  while a[i] == b[i]:
    if a[i] == '\0':
      return true
    inc i

  false


proc deviceKindForPath(path: cstring): U32 =
  if pathEq(path, "/dev/stdin"):
    return SysFdKindStdin
  if pathEq(path, "/dev/stdout"):
    return SysFdKindStdout
  if pathEq(path, "/dev/stderr"):
    return SysFdKindStderr
  if pathEq(path, "/dev/console"):
    return SysFdKindConsole

  SysFdKindFile


proc validFd(fd: I32): bool =
  fd >= 0 and fd < I32(SysFdMax) and currentProc != nil and
    currentProc.files.entries[U32(fd)].used


proc allocFd(): I32 =
  if currentProc == nil:
    return -1

  var i = U32(3)
  while i < SysFdMax:
    if not currentProc.files.entries[i].used:
      return I32(i)

    inc i

  -1


proc findFreeFd(exclude: I32 = -1): I32 =
  if currentProc == nil:
    return -1

  var i = U32(3)
  while i < SysFdMax:
    if I32(i) != exclude and not currentProc.files.entries[i].used:
      return I32(i)

    inc i

  -1


proc refreshFdSize(entry: var FdEntry): bool =
  let size = serviceReadFileToKernel(fdPath(entry), addr fdFileBuf[0], SysFileIoMax)
  if size < 0:
    return false

  entry.size = U64(size)
  true


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

    currentProc.files.entries[U32(fd)] = entry
    return U64(fd)

  if (flags and (SysOpenCreate or SysOpenTrunc)) != 0:
    if serviceWriteFile(fdPath(entry), addr fdFileBuf[0], 0) != 0:
      return U64(-1'i64)

  if not refreshFdSize(entry):
    return U64(-1'i64)

  if (flags and SysOpenAppend) != 0:
    entry.offset = entry.size

  currentProc.files.entries[U32(fd)] = entry
  U64(fd)


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

  let size = serviceReadFileToKernel(fdPath(entry[]), addr fdFileBuf[0], SysFileIoMax)
  if size < 0:
    return U64(-1'i64)

  entry.size = U64(size)
  if entry.offset >= entry.size:
    return 0

  let remain = entry.size - entry.offset
  let readLen =
    if len > remain:
      remain
    else:
      len

  if copyToUser(bufVal, cast[pointer](cast[U64](addr fdFileBuf[0]) + entry.offset), readLen) != 0:
    return U64(-1'i64)

  entry.offset += readLen
  readLen


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

  var currentSize = U64(0)
  if entry.size > 0:
    let size = serviceReadFileToKernel(fdPath(entry[]), addr fdFileBuf[0], SysFileIoMax)
    if size < 0:
      return U64(-1'i64)
    currentSize = U64(size)

  if entry.offset > currentSize:
    while currentSize < entry.offset and currentSize < SysFileIoMax:
      fdFileBuf[currentSize] = 0
      inc currentSize

  if entry.offset + len > SysFileIoMax:
    return U64(-1'i64)

  if copyFromUser(cast[pointer](cast[U64](addr fdFileBuf[0]) + entry.offset), bufVal, len) != 0:
    return U64(-1'i64)

  let newSize =
    if entry.offset + len > currentSize:
      entry.offset + len
    else:
      currentSize

  let rc = serviceWriteFile(fdPath(entry[]), addr fdFileBuf[0], newSize)
  if I32(rc) != 0:
    return U64(-1'i64)

  entry.offset += len
  entry.size = newSize
  len


proc syscallClose*(fdVal: U64): U64 =
  if not validFd(I32(fdVal)):
    return U64(-1'i64)

  releaseFdEntry(currentProc.files.entries[U32(fdVal)])
  currentProc.files.entries[U32(fdVal)] = FdEntry()
  0


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
