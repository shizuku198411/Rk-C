## Centralizes validation for filesystem service requests and responses.

type
  FsValidationError* = enum
    fsValidationOk = 0
    fsValidationNull
    fsValidationBadPath
    fsValidationBadSize
    fsValidationBadCapacity
    fsValidationBadData
    fsValidationBadOperation
    fsValidationBadResult


## Checks that an embedded fixed-size path field is NUL-terminated.
proc validateFsPathField*(path: ptr UncheckedArray[char]): bool =
  path != nil and fixedCStringHasNul(path, U64(SysFsPathMax))


## Validates the shape of a filesystem service request before it is queued.
proc validateFsRequestShape*(
  op: U32,
  path: cstring,
  data: pointer,
  size,
  capacity: U64
): bool =
  if path == nil:
    return false

  case op
  of SysFsOpLs:
    capacity <= SysFsDataMax and capacity mod U64(sizeof(FsDirEntry)) == U64(0)
  of SysFsOpMkdir, SysFsOpUnlink, SysFsOpRmdir, SysFsOpFileSize:
    data == nil and size == U64(0) and capacity == U64(0)
  of SysFsOpReadFile:
    data == nil and size == U64(0) and capacity <= SysFsDataMax
  of SysFsOpReadRange:
    data == nil and capacity <= SysFsDataMax
  of SysFsOpWriteFile:
    data != nil and size <= SysFsDataMax and (capacity and U64(not SysFsWriteKnownFlags)) == U64(0)
  of SysFsOpWriteRange:
    data != nil and size <= SysFsDataMax
  of SysFsOpRename:
    data != nil and size > U64(0) and size <= SysFsPathMax and capacity == U64(0)
  of SysFsOpChmod:
    data == nil and capacity == U64(0)
  of SysFsOpChown:
    data == nil
  else:
    false


## Validates a raw read-range request copied from the filesystem service.
proc validateReadRangeRequest*(req: ptr SysFsRequest): bool =
  if req == nil:
    return false
  if req.capacity > SysFsDataMax:
    return false

  validateFsPathField(cast[ptr UncheckedArray[char]](addr req.path[0]))


## Validates a raw write-range request copied from the filesystem service.
proc validateWriteRangeRequest*(req: ptr SysFsRequest): bool =
  if req == nil:
    return false
  if req.size > SysFsDataMax:
    return false

  validateFsPathField(cast[ptr UncheckedArray[char]](addr req.path[0]))


## Checks that a read response result fits the requested capacity and IPC data area.
proc validateReadResponse*(resultValue: I32, capacity: U64): bool =
  if resultValue < 0:
    return false

  U64(resultValue) <= capacity and U64(resultValue) <= SysFsDataMax


## Checks that a directory listing response fits the requested byte capacity.
proc validateDirResponse*(resultValue: I32, entryBytes: U64): bool =
  if resultValue < 0:
    return false

  let bytes = U64(resultValue) * U64(sizeof(FsDirEntry))
  bytes <= entryBytes and bytes <= SysFsDataMax


## Validates a filesystem service response against its original request.
proc validateFsResponseShape*(req: ptr SysFsRequest, resp: ptr SysFsResponse): bool =
  if req == nil or resp == nil:
    return false
  if resp.size > SysFsDataMax:
    return false
  if resp.result < 0:
    return true

  let resultValue = U64(resp.result)
  case req.op
  of SysFsOpLs:
    let maxEntries = req.capacity div U64(sizeof(FsDirEntry))
    resultValue <= maxEntries and resultValue * U64(sizeof(FsDirEntry)) <= SysFsDataMax
  of SysFsOpReadFile, SysFsOpReadRange:
    resultValue <= req.capacity and resultValue <= SysFsDataMax
  of SysFsOpFileSize:
    true
  of SysFsOpMkdir, SysFsOpUnlink, SysFsOpRmdir, SysFsOpWriteFile,
      SysFsOpWriteRange, SysFsOpRename, SysFsOpChmod, SysFsOpChown:
    resultValue <= U64(high(I32))
  else:
    false
