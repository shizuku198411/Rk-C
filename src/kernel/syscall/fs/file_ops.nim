import ../../../lib/types
import ../../../lib/syscall_types
import ../../../lib/calc
import ../../../lib/fs_permissions
import ../../../lib/user_ids
import ../../dev/timer
import ../../fs/fs
import ../../lib/fd_helpers
import ../../syscall/fs/fs_service_ops
import ../../syscall/io/console_io
import ../../mm/usercopy
import ../../task/process

const
  SysPathMax = U64(128)
  SysDirEntryMax = U64(32)
  SysFileIoMax = U64(4096)
  KnownPollEvents = SysPollFdRead or SysPollFdWrite or SysPollIpcRead or
    SysPollPidExit or SysPollTimer

var
  pathBuf: array[SysPathMax, char]
  fileBuf: array[SysFileIoMax, U8]
  fdFileBuf: array[SysFileIoMax, U8]
  pollEvents: array[SysPollMaxEvents, SysPollEvent]
  renamePathBuf: array[SysPathMax, char]


proc readPath(pathVal: U64, defaultRoot: bool = false): cstring =
  if pathVal == 0:
    if defaultRoot:
      return "/"
    return nil

  if copyUserCString(addr pathBuf[0], pathVal, SysPathMax) < 0:
    return nil

  cast[cstring](addr pathBuf[0])


proc canReadPath(path: cstring): bool =
  currentProc != nil and fsCanReadPath(currentProc.identity.uid, currentProc.identity.gid, path)


proc canWritePath(path: cstring): bool =
  currentProc != nil and fsCanWritePath(currentProc.identity.uid, currentProc.identity.gid, path)


proc canSearchDirPath(path: cstring): bool =
  currentProc != nil and fsCanSearchDirPath(currentProc.identity.uid, currentProc.identity.gid, path)


proc canModifyParentPath(path: cstring): bool =
  currentProc != nil and fsCanModifyParentPath(currentProc.identity.uid, currentProc.identity.gid, path)


proc canListPath(path: cstring): bool =
  canReadPath(path) and canSearchDirPath(path)


proc canCreateOrWritePath(path: cstring, flags: U32): bool =
  let existingSize = serviceFileSizeToKernel(path)
  if existingSize >= 0:
    return canWritePath(path)

  (flags and SysFsWriteCreate) != U32(0) and canModifyParentPath(path)


proc canOpenFilePath(path: cstring, flags: U32): bool =
  let existingSize = serviceFileSizeToKernel(path)
  let willCreate = existingSize < 0 and (flags and SysOpenCreate) != U32(0)

  if (flags and SysOpenRead) != 0 and not willCreate and not canReadPath(path):
    return false

  if (flags and SysOpenWrite) != 0:
    if existingSize >= 0:
      if not canWritePath(path):
        return false
    elif not canModifyParentPath(path):
      return false

  true


proc canOpenDevicePath(path: cstring, flags: U32): bool =
  if (flags and SysOpenRead) != 0 and not canReadPath(path):
    return false
  if (flags and SysOpenWrite) != 0 and not canWritePath(path):
    return false

  true


proc syscallLs*(pathVal, entriesVal, maxEntries: U64): U64 =
  if entriesVal == 0 or maxEntries == 0:
    return U64(-1'i64)

  let requestedOffset = maxEntries shr U64(32)
  let requestedMax = maxEntries and U64(0xffffffff'u64)
  if requestedMax == U64(0):
    return U64(-1'i64)

  let path = readPath(pathVal, true)
  if path == nil:
    return U64(-1'i64)
  if not canListPath(path):
    return U64(-1'i64)

  let countMax =
    if requestedMax > SysDirEntryMax:
      SysDirEntryMax
    else:
      requestedMax
  serviceLs(path, entriesVal, countMax, requestedOffset)


proc syscallMkdir*(path: U64): U64 =
  let copiedPath = readPath(path)
  if copiedPath == nil:
    return U64(-1'i64)
  if not canModifyParentPath(copiedPath):
    return U64(-1'i64)

  serviceMkdir(copiedPath)


proc syscallUnlink*(path: U64): U64 =
  let copiedPath = readPath(path)
  if copiedPath == nil:
    return U64(-1'i64)
  if not fsCanRemovePath(currentProc.identity.uid, currentProc.identity.gid, copiedPath):
    return U64(-1'i64)

  serviceUnlink(copiedPath)


proc syscallRmdir*(path: U64): U64 =
  let copiedPath = readPath(path)
  if copiedPath == nil:
    return U64(-1'i64)
  if not fsCanRemovePath(currentProc.identity.uid, currentProc.identity.gid, copiedPath):
    return U64(-1'i64)

  serviceRmdir(copiedPath)


proc syscallReadFile*(path, buf, capacity: U64): U64 =
  if buf == 0 or capacity > SysFileIoMax:
    return U64(-1'i64)

  let copiedPath = readPath(path)
  if copiedPath == nil:
    return U64(-1'i64)
  if not canReadPath(copiedPath):
    return U64(-1'i64)

  serviceReadFile(copiedPath, buf, capacity)


proc unpackWriteSizeFlags(value: U64, size: var U64, flags: var U32) =
  size = value and U64(0xffffffff'u64)
  flags = U32(value shr U64(32))
  if flags == U32(0):
    flags = SysFsWriteDefault


proc syscallWriteFile*(path, buf, sizeFlags: U64): U64 =
  var size: U64
  var flags: U32
  unpackWriteSizeFlags(sizeFlags, size, flags)

  if size > SysFileIoMax:
    return U64(-1'i64)

  let copiedPath = readPath(path)
  if copiedPath == nil:
    return U64(-1'i64)
  if not canCreateOrWritePath(copiedPath, flags):
    return U64(-1'i64)
  if copyFromUser(addr fileBuf[0], buf, size) != 0:
    return U64(-1'i64)

  serviceWriteFile(copiedPath, addr fileBuf[0], size, flags)


proc syscallRename*(oldPathVal, newPathVal: U64): U64 =
  let oldPath = readPath(oldPathVal)
  if oldPath == nil:
    return U64(-1'i64)
  if copyUserCString(addr renamePathBuf[0], newPathVal, SysPathMax) < 0:
    return U64(-1'i64)
  if not fsCanRemovePath(currentProc.identity.uid, currentProc.identity.gid, oldPath) or
      not canModifyParentPath(cast[cstring](addr renamePathBuf[0])):
    return U64(-1'i64)

  serviceRename(oldPath, cast[cstring](addr renamePathBuf[0]))


proc syscallChmod*(pathVal, modeVal: U64): U64 =
  let path = readPath(pathVal)
  if path == nil:
    setLastError(SysErrInval)
    return U64(-1'i64)

  let mode = U32(modeVal) and FsModeChmodMask
  if currentProc == nil or not fsCanChmodPath(currentProc.identity.uid, currentProc.identity.gid, path):
    setLastError(SysErrPerm)
    return U64(-1'i64)

  serviceChmod(path, mode)


proc unpackUidGid(value: U64, uid, gid: var U32) =
  uid = U32(value and U64(0xffffffff'u64))
  gid = U32(value shr U64(32))


proc validChownTarget(uid, gid: U32): bool =
  (uid == RootUid and gid == RootGid) or (uid == UserUid and gid == UserGid)


proc syscallChown*(pathVal, uidGidVal: U64): U64 =
  if currentProc == nil:
    setLastError(SysErrInval)
    return U64(-1'i64)

  if currentProc.identity.uid != RootUid:
    setLastError(SysErrPerm)
    return U64(-1'i64)

  let path = readPath(pathVal)
  if path == nil:
    setLastError(SysErrInval)
    return U64(-1'i64)

  var uid: U32
  var gid: U32
  unpackUidGid(uidGidVal, uid, gid)
  if not validChownTarget(uid, gid):
    setLastError(SysErrInval)
    return U64(-1'i64)

  let rc = serviceChown(path, uid, gid)
  if rc != U64(0):
    setLastError(SysErrPerm)
    return U64(-1'i64)

  clearLastError()
  U64(0)


proc refreshFdSize(entry: var FdEntry): bool =
  let size = serviceFileSizeToKernel(fdPath(entry))
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


proc fdReadReady(fd: I32): bool =
  if not validFd(fd):
    return false

  let entry = addr currentProc.files.entries[U32(fd)]
  if (entry.flags and SysOpenRead) == 0:
    return false

  if entry.kind == SysFdKindPipe:
    return pipeReadable(entry.pipeId)
  if entry.kind == SysFdKindFile:
    return true

  false


proc fdWriteReady(fd: I32): bool =
  if not validFd(fd):
    return false

  let entry = addr currentProc.files.entries[U32(fd)]
  if (entry.flags and SysOpenWrite) == 0:
    return false

  if entry.kind == SysFdKindPipe:
    return pipeWritable(entry.pipeId)
  if entry.kind == SysFdKindStdout or entry.kind == SysFdKindStderr or
      entry.kind == SysFdKindConsole or entry.kind == SysFdKindFile:
    return true

  false


proc evaluatePollEvents(count: U64, timedOut: bool): I32 =
  var ready = I32(0)
  var i = U32(0)
  while U64(i) < count:
    var revents = U32(0)
    let requested = pollEvents[i].events
    let target = pollEvents[i].target

    if (requested and SysPollFdRead) != 0:
      if not validFd(target):
        revents = revents or SysPollError
      elif fdReadReady(target):
        revents = revents or SysPollFdRead

    if (requested and SysPollFdWrite) != 0:
      if not validFd(target):
        revents = revents or SysPollError
      elif fdWriteReady(target):
        revents = revents or SysPollFdWrite

    if (requested and SysPollIpcRead) != 0:
      if currentProc != nil and currentProc.ipc.count > 0:
        revents = revents or SysPollIpcRead

    if (requested and SysPollPidExit) != 0:
      let p = findProcessByPid(target)
      if p == nil:
        revents = revents or SysPollError
      elif p.state == procZombie:
        revents = revents or SysPollPidExit

    if (requested and SysPollTimer) != 0 and timedOut:
      revents = revents or SysPollTimer

    if (requested and not KnownPollEvents) != 0:
      revents = revents or SysPollError

    pollEvents[i].revents = revents
    if revents != 0:
      inc ready
    inc i

  ready


proc copyPollEventsToUser(eventsVal, count: U64): bool =
  let bytes = count * U64(sizeof(SysPollEvent))
  copyToUser(eventsVal, addr pollEvents[0], bytes) == 0


proc syscallPoll*(eventsVal, count, timeoutTicks: U64): U64 =
  if currentProc == nil or eventsVal == 0 or count == 0 or count > U64(SysPollMaxEvents):
    return U64(-1'i64)

  let bytes = count * U64(sizeof(SysPollEvent))
  if copyFromUser(addr pollEvents[0], eventsVal, bytes) != 0:
    return U64(-1'i64)

  var ready = evaluatePollEvents(count, false)
  if ready > 0 or timeoutTicks == 0:
    if not copyPollEventsToUser(eventsVal, count):
      return U64(-1'i64)
    return U64(ready)

  let deadline = saturatingAddU64(timerTickCount, timeoutTicks)
  while true:
    sleepCurrentForPoll(deadline)
    let timedOut = timerTickCount >= deadline
    ready = evaluatePollEvents(count, timedOut)
    if ready > 0 or timedOut:
      if not copyPollEventsToUser(eventsVal, count):
        return U64(-1'i64)
      return U64(ready)
