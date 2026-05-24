## Handles path-oriented filesystem syscalls and access checks.

## Reads path.
proc readPath(pathVal: U64, defaultRoot: bool = false): cstring =
  if pathVal == 0:
    if defaultRoot:
      return "/"
    return nil

  if copyUserCString(addr pathBuf[0], pathVal, SysPathMax) < 0:
    return nil

  cast[cstring](addr pathBuf[0])


## Checks whether read path is allowed.
proc canReadPath(path: cstring): bool =
  currentProc != nil and fsCanReadPath(currentProc.identity.uid, currentProc.identity.gid, path)


## Checks whether write path is allowed.
proc canWritePath(path: cstring): bool =
  currentProc != nil and fsCanWritePath(currentProc.identity.uid, currentProc.identity.gid, path)


## Checks whether search dir path is allowed.
proc canSearchDirPath(path: cstring): bool =
  currentProc != nil and fsCanSearchDirPath(currentProc.identity.uid, currentProc.identity.gid, path)


## Checks whether modify parent path is allowed.
proc canModifyParentPath(path: cstring): bool =
  currentProc != nil and fsCanModifyParentPath(currentProc.identity.uid, currentProc.identity.gid, path)


## Checks whether list path is allowed.
proc canListPath(path: cstring): bool =
  canReadPath(path) and canSearchDirPath(path)


## Checks whether create or write path is allowed.
proc canCreateOrWritePath(path: cstring, flags: U32): bool =
  let existingSize = serviceFileSizeToKernel(path)
  if existingSize >= 0:
    return canWritePath(path)

  (flags and SysFsWriteCreate) != U32(0) and canModifyParentPath(path)


## Checks whether open file path is allowed.
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


## Checks whether open device path is allowed.
proc canOpenDevicePath(path: cstring, flags: U32): bool =
  if (flags and SysOpenRead) != 0 and not canReadPath(path):
    return false
  if (flags and SysOpenWrite) != 0 and not canWritePath(path):
    return false

  true


## Handles the ls syscall operation.
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


## Handles the mkdir syscall operation.
proc syscallMkdir*(path: U64): U64 =
  let copiedPath = readPath(path)
  if copiedPath == nil:
    return U64(-1'i64)
  if not canModifyParentPath(copiedPath):
    return U64(-1'i64)

  serviceMkdir(copiedPath)


## Handles the unlink syscall operation.
proc syscallUnlink*(path: U64): U64 =
  let copiedPath = readPath(path)
  if copiedPath == nil:
    return U64(-1'i64)
  if not fsCanRemovePath(currentProc.identity.uid, currentProc.identity.gid, copiedPath):
    return U64(-1'i64)

  serviceUnlink(copiedPath)


## Handles the rmdir syscall operation.
proc syscallRmdir*(path: U64): U64 =
  let copiedPath = readPath(path)
  if copiedPath == nil:
    return U64(-1'i64)
  if not fsCanRemovePath(currentProc.identity.uid, currentProc.identity.gid, copiedPath):
    return U64(-1'i64)

  serviceRmdir(copiedPath)


## Handles the read file syscall operation.
proc syscallReadFile*(path, buf, capacity: U64): U64 =
  if buf == 0 or capacity > SysFileIoMax:
    return U64(-1'i64)

  let copiedPath = readPath(path)
  if copiedPath == nil:
    return U64(-1'i64)
  if not canReadPath(copiedPath):
    return U64(-1'i64)

  serviceReadFile(copiedPath, buf, capacity)


## Implements the unpack write size flags kernel helper.
proc unpackWriteSizeFlags(value: U64, size: var U64, flags: var U32) =
  size = value and U64(0xffffffff'u64)
  flags = U32(value shr U64(32))
  if flags == U32(0):
    flags = SysFsWriteDefault


## Handles the write file syscall operation.
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


## Handles the rename syscall operation.
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


## Handles the chmod syscall operation.
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


## Implements the unpack uid gid kernel helper.
proc unpackUidGid(value: U64, uid, gid: var U32) =
  uid = U32(value and U64(0xffffffff'u64))
  gid = U32(value shr U64(32))


## Handles the chown syscall operation.
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

  let rc = serviceChown(path, uid, gid)
  if rc != U64(0):
    setLastError(SysErrPerm)
    return U64(-1'i64)

  clearLastError()
  U64(0)


