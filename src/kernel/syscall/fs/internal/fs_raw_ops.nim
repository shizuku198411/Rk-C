## Handles privileged raw filesystem access used by the service process.

## Handles the raw ls syscall operation.
proc syscallRawLs*(pathVal, entriesVal, maxEntriesVal: U64): U64 =
  var maxEntries: U64
  var offset: U64
  unpackLsLimitOffset(maxEntriesVal, maxEntries, offset)

  if not canSyscallRawFs() or pathVal == 0 or entriesVal == 0 or maxEntries == 0:
    return U64(-1'i64)

  var pathBuf: array[SysFsPathMax, char]
  if not copyUserPath(pathVal, pathBuf):
    return U64(-1'i64)

  let countMax =
    if maxEntries > U64(FsRawDirEntryMax):
      U64(FsRawDirEntryMax)
    else:
      maxEntries
  let count = rawLsKernel(cast[cstring](addr pathBuf[0]), addr rawEntries[0], countMax, offset)
  if count < 0:
    return U64(-1'i64)

  let bytes = U64(count) * U64(sizeof(FsDirEntry))
  if copyToUser(entriesVal, addr rawEntries[0], bytes) != 0:
    return U64(-1'i64)

  U64(count)


## Handles the raw mkdir syscall operation.
proc syscallRawMkdir*(pathVal: U64): U64 =
  if not canSyscallRawFs() or pathVal == 0:
    return U64(-1'i64)

  var pathBuf: array[SysFsPathMax, char]
  if not copyUserPath(pathVal, pathBuf):
    return U64(-1'i64)

  U64(fsMkdir(cast[cstring](addr pathBuf[0])))


## Handles the raw unlink syscall operation.
proc syscallRawUnlink*(pathVal: U64): U64 =
  if not canSyscallRawFs() or pathVal == 0:
    return U64(-1'i64)

  var pathBuf: array[SysFsPathMax, char]
  if not copyUserPath(pathVal, pathBuf):
    return U64(-1'i64)

  U64(fsUnlink(cast[cstring](addr pathBuf[0])))


## Handles the raw rmdir syscall operation.
proc syscallRawRmdir*(pathVal: U64): U64 =
  if not canSyscallRawFs() or pathVal == 0:
    return U64(-1'i64)

  var pathBuf: array[SysFsPathMax, char]
  if not copyUserPath(pathVal, pathBuf):
    return U64(-1'i64)

  U64(fsRmdir(cast[cstring](addr pathBuf[0])))


## Handles the raw read file syscall operation.
proc syscallRawReadFile*(pathVal, bufVal, capacity: U64): U64 =
  if not canSyscallRawFs() or pathVal == 0 or bufVal == 0 or capacity > SysFsDataMax:
    return U64(-1'i64)

  var pathBuf: array[SysFsPathMax, char]
  if not copyUserPath(pathVal, pathBuf):
    return U64(-1'i64)

  let readLen = rawReadFileKernel(cast[cstring](addr pathBuf[0]), addr rawFileBuf[0], capacity)
  if readLen < 0:
    return U64(-1'i64)
  if copyToUser(bufVal, addr rawFileBuf[0], U64(readLen)) != 0:
    return U64(-1'i64)

  U64(readLen)


## Handles the raw file size syscall operation.
proc syscallRawFileSize*(pathVal: U64): U64 =
  if not canSyscallRawFs() or pathVal == 0:
    return U64(-1'i64)

  var pathBuf: array[SysFsPathMax, char]
  if not copyUserPath(pathVal, pathBuf):
    return U64(-1'i64)

  let size = rawFileSizeKernel(cast[cstring](addr pathBuf[0]))
  if size < 0:
    return U64(-1'i64)

  U64(size)


## Handles the raw read range syscall operation.
proc syscallRawReadRange*(reqVal: U64): U64 =
  if not canSyscallRawFs() or reqVal == 0:
    return U64(-1'i64)

  var req: SysFsRequest
  if copyFromUser(addr req, reqVal, U64(sizeof(SysFsRequest))) != 0:
    return U64(-1'i64)
  if not validateReadRangeRequest(addr req):
    return U64(-1'i64)

  let readLen = rawReadFileRangeKernel(
    cast[cstring](addr req.path[0]),
    addr req.data[0],
    req.size,
    req.capacity,
  )
  if readLen < 0:
    return U64(-1'i64)
  if copyToUser(reqVal, addr req, U64(sizeof(SysFsRequest))) != 0:
    return U64(-1'i64)

  U64(readLen)


## Handles the raw write range syscall operation.
proc syscallRawWriteRange*(reqVal: U64): U64 =
  if not canSyscallRawFs() or reqVal == 0:
    return U64(-1'i64)

  var req: SysFsRequest
  if copyFromUser(addr req, reqVal, U64(sizeof(SysFsRequest))) != 0:
    return U64(-1'i64)
  if not validateWriteRangeRequest(addr req):
    return U64(-1'i64)

  U64(rawWriteFileRangeKernel(
    cast[cstring](addr req.path[0]),
    addr req.data[0],
    req.capacity,
    req.size,
  ))


## Handles the raw write file syscall operation.
proc syscallRawWriteFile*(pathVal, bufVal, sizeFlags: U64): U64 =
  var size: U64
  var flags: U32
  unpackWriteSizeFlags(sizeFlags, size, flags)

  if not canSyscallRawFs() or pathVal == 0 or size > SysFsDataMax:
    return U64(-1'i64)

  var pathBuf: array[SysFsPathMax, char]
  if not copyUserPath(pathVal, pathBuf):
    return U64(-1'i64)
  if copyFromUser(addr rawFileBuf[0], bufVal, size) != 0:
    return U64(-1'i64)

  U64(fsWriteFileWithFlags(cast[cstring](addr pathBuf[0]), addr rawFileBuf[0], size, flags))


## Handles the raw rename syscall operation.
proc syscallRawRename*(oldPathVal, newPathVal: U64): U64 =
  if not canSyscallRawFs() or oldPathVal == 0 or newPathVal == 0:
    return U64(-1'i64)

  var oldPathBuf: array[SysFsPathMax, char]
  var newPathBuf: array[SysFsPathMax, char]
  if not copyUserPathPair(oldPathVal, newPathVal, oldPathBuf, newPathBuf):
    return U64(-1'i64)

  U64(rawRenameKernel(cast[cstring](addr oldPathBuf[0]), cast[cstring](addr newPathBuf[0])))


## Handles the raw chmod syscall operation.
proc syscallRawChmod*(pathVal, modeVal: U64): U64 =
  if not canSyscallRawFs() or pathVal == 0:
    return U64(-1'i64)

  var pathBuf: array[SysFsPathMax, char]
  if not copyUserPath(pathVal, pathBuf):
    return U64(-1'i64)

  U64(rawChmodKernel(cast[cstring](addr pathBuf[0]), U32(modeVal)))


## Handles the raw chown syscall operation.
proc syscallRawChown*(pathVal, uidGidVal: U64): U64 =
  if not canSyscallRawFs() or pathVal == 0:
    return U64(-1'i64)

  var pathBuf: array[SysFsPathMax, char]
  if not copyUserPath(pathVal, pathBuf):
    return U64(-1'i64)

  let uid = U32(uidGidVal and U64(0xffffffff'u64))
  let gid = U32(uidGidVal shr U64(32))
  U64(rawChownKernel(cast[cstring](addr pathBuf[0]), uid, gid))
