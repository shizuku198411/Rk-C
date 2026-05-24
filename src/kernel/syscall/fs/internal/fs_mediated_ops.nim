## Forwards filesystem operations through the registered filesystem service.

## Implements the service ls kernel helper.
proc serviceLs*(path: cstring, entriesVal, maxEntries: U64, offset: U64 = 0): U64 =
  if maxEntries == 0:
    return 0

  let chunkMax =
    if maxEntries > U64(FsRawDirEntryMax):
      U64(FsRawDirEntryMax)
    else:
      maxEntries
  let entryBytes = chunkMax * U64(sizeof(FsDirEntry))
  let req = queueFsRequest(SysFsOpLs, path, nil, offset, entryBytes)
  if req == nil:
    if not canFallbackToRawFs():
      return U64(-1'i64)

    let count = rawLsKernel(path, addr rawEntries[0], chunkMax, offset)
    if count < 0:
      return U64(-1'i64)
    let bytes = U64(count) * U64(sizeof(FsDirEntry))
    if copyToUser(entriesVal, addr rawEntries[0], bytes) != 0:
      return U64(-1'i64)
    return U64(count)

  let resp = waitFsResponse(req)
  if resp == nil or resp.result < 0:
    finishPending(req)
    return U64(-1'i64)

  let bytes = U64(resp.result) * U64(sizeof(FsDirEntry))
  if copyToUser(entriesVal, addr resp.data[0], bytes) != 0:
    finishPending(req)
    return U64(-1'i64)

  let outValue = U64(resp.result)
  finishPending(req)
  outValue


## Implements the service ls to kernel kernel helper.
proc serviceLsToKernel*(path: cstring, dst: ptr FsDirEntry, maxEntries: U64, offset: U64 = 0): I32 =
  if dst == nil or maxEntries == 0:
    return -1

  let chunkMax =
    if maxEntries > U64(FsRawDirEntryMax):
      U64(FsRawDirEntryMax)
    else:
      maxEntries
  let entryBytes = chunkMax * U64(sizeof(FsDirEntry))
  if entryBytes > SysFsDataMax:
    return -1

  let req = queueFsRequest(SysFsOpLs, path, nil, offset, entryBytes)
  if req == nil:
    if not canFallbackToRawFs():
      return -1

    return I32(rawLsKernel(path, dst, chunkMax, offset))

  let resp = waitFsResponse(req)
  if resp == nil or resp.result < 0:
    finishPending(req)
    return -1

  let bytes = U64(resp.result) * U64(sizeof(FsDirEntry))
  if bytes > entryBytes or bytes > SysFsDataMax:
    finishPending(req)
    return -1

  discard copyMem(dst, addr resp.data[0], bytes)
  let outValue = resp.result
  finishPending(req)
  outValue


## Implements the service mkdir kernel helper.
proc serviceMkdir*(path: cstring): U64 =
  let req = queueFsRequest(SysFsOpMkdir, path, nil, 0, 0)
  if req == nil:
    if not canFallbackToRawFs():
      return U64(-1'i64)

    let rc = fsMkdir(path)
    if rc == 0 and currentProc != nil and rawChownKernel(path, currentProc.identity.uid, currentProc.identity.gid) < 0:
      discard fsRmdir(path)
      return U64(-1'i64)

    return U64(rc)

  let resp = waitFsResponse(req)
  let outValue =
    if resp == nil:
      U64(-1'i64)
    else:
      U64(resp.result)

  finishPending(req)
  outValue


## Implements the service unlink kernel helper.
proc serviceUnlink*(path: cstring): U64 =
  let req = queueFsRequest(SysFsOpUnlink, path, nil, 0, 0)
  if req == nil:
    if not canFallbackToRawFs():
      return U64(-1'i64)

    return U64(fsUnlink(path))

  let resp = waitFsResponse(req)
  let outValue =
    if resp == nil:
      U64(-1'i64)
    else:
      U64(resp.result)

  finishPending(req)
  outValue


## Implements the service rmdir kernel helper.
proc serviceRmdir*(path: cstring): U64 =
  let req = queueFsRequest(SysFsOpRmdir, path, nil, 0, 0)
  if req == nil:
    if not canFallbackToRawFs():
      return U64(-1'i64)

    return U64(fsRmdir(path))

  let resp = waitFsResponse(req)
  let outValue =
    if resp == nil:
      U64(-1'i64)
    else:
      U64(resp.result)

  finishPending(req)
  outValue


## Implements the service read file kernel helper.
proc serviceReadFile*(path: cstring, bufVal, capacity: U64): U64 =
  let req = queueFsRequest(SysFsOpReadFile, path, nil, 0, capacity)
  if req == nil:
    if not canFallbackToRawFs():
      return U64(-1'i64)

    let readLen = rawReadFileKernel(path, addr rawFileBuf[0], capacity)
    if readLen < 0:
      return U64(-1'i64)
    if copyToUser(bufVal, addr rawFileBuf[0], U64(readLen)) != 0:
      return U64(-1'i64)
    return U64(readLen)

  let resp = waitFsResponse(req)
  if resp == nil or resp.result < 0:
    finishPending(req)
    return U64(-1'i64)

  if copyToUser(bufVal, addr resp.data[0], U64(resp.result)) != 0:
    finishPending(req)
    return U64(-1'i64)

  let outValue = U64(resp.result)
  finishPending(req)
  outValue


## Implements the service read file to kernel kernel helper.
proc serviceReadFileToKernel*(path: cstring, dst: pointer, capacity: U64): I32 =
  if dst == nil or capacity > SysFsDataMax:
    return -1

  let req = queueFsRequest(SysFsOpReadFile, path, nil, 0, capacity)
  if req == nil:
    if not canFallbackToRawFs():
      return -1

    return I32(rawReadFileKernel(path, dst, capacity))

  let resp = waitFsResponse(req)
  if resp == nil or resp.result < 0:
    finishPending(req)
    return -1

  discard copyMem(dst, addr resp.data[0], U64(resp.result))
  let outValue = resp.result
  finishPending(req)
  outValue


## Implements the service file size to kernel kernel helper.
proc serviceFileSizeToKernel*(path: cstring): I32 =
  let req = queueFsRequest(SysFsOpFileSize, path, nil, 0, 0)
  if req == nil:
    if not canFallbackToRawFs():
      return -1

    return I32(rawFileSizeKernel(path))

  let resp = waitFsResponse(req)
  let outValue =
    if resp == nil:
      -1'i32
    else:
      resp.result

  finishPending(req)
  outValue


## Implements the service read file range to kernel kernel helper.
proc serviceReadFileRangeToKernel*(path: cstring, dst: pointer, offset, capacity: U64): I32 =
  if dst == nil or capacity > SysFsDataMax:
    return -1

  let req = queueFsRequest(SysFsOpReadRange, path, nil, offset, capacity)
  if req == nil:
    if not canFallbackToRawFs():
      return -1

    return I32(rawReadFileRangeKernel(path, dst, offset, capacity))

  let resp = waitFsResponse(req)
  if resp == nil or resp.result < 0:
    finishPending(req)
    return -1

  discard copyMem(dst, addr resp.data[0], U64(resp.result))
  let outValue = resp.result
  finishPending(req)
  outValue


## Implements the service write file kernel helper.
proc serviceWriteFile*(path: cstring, data: pointer, size: U64, flags: U32 = SysFsWriteDefault): U64 =
  let req = queueFsRequest(SysFsOpWriteFile, path, data, size, U64(flags))
  if req == nil:
    if not canFallbackToRawFs():
      return U64(-1'i64)

    let created = rawFileSizeKernel(path) < 0
    let rc = fsWriteFileWithFlags(path, data, size, flags)
    if rc == 0 and created and currentProc != nil and
        rawChownKernel(path, currentProc.identity.uid, currentProc.identity.gid) < 0:
      discard fsUnlink(path)
      return U64(-1'i64)

    return U64(rc)

  let resp = waitFsResponse(req)
  let outValue =
    if resp == nil:
      U64(-1'i64)
    else:
      U64(resp.result)

  finishPending(req)
  outValue


## Implements a mediated file range write for streaming descriptor output.
proc serviceWriteFileRange*(path: cstring, data: pointer, offset, size: U64): U64 =
  let req = queueFsRequest(SysFsOpWriteRange, path, data, size, offset)
  if req == nil:
    if not canFallbackToRawFs():
      return U64(-1'i64)

    return U64(rawWriteFileRangeKernel(path, data, offset, size))

  let resp = waitFsResponse(req)
  let outValue =
    if resp == nil:
      U64(-1'i64)
    else:
      U64(resp.result)

  finishPending(req)
  outValue


## Implements the service rename kernel helper.
proc serviceRename*(oldPath, newPath: cstring): U64 =
  if not copyCString(renamePathBuf, newPath):
    return U64(-1'i64)

  let req = queueFsRequest(
    SysFsOpRename,
    oldPath,
    addr renamePathBuf[0],
    U64(cstrlen(cast[cstring](addr renamePathBuf[0])) + U64(1)),
    0,
  )
  if req == nil:
    if not canFallbackToRawFs():
      return U64(-1'i64)

    return U64(rawRenameKernel(oldPath, newPath))

  let resp = waitFsResponse(req)
  let outValue =
    if resp == nil:
      U64(-1'i64)
    else:
      U64(resp.result)

  finishPending(req)
  outValue


## Implements the service chmod kernel helper.
proc serviceChmod*(path: cstring, mode: U32): U64 =
  let req = queueFsRequest(SysFsOpChmod, path, nil, U64(mode), 0)
  if req == nil:
    if not canFallbackToRawFs():
      return U64(-1'i64)

    return U64(rawChmodKernel(path, mode))

  let resp = waitFsResponse(req)
  let outValue =
    if resp == nil:
      U64(-1'i64)
    else:
      U64(resp.result)

  finishPending(req)
  outValue


## Implements the service chown kernel helper.
proc serviceChown*(path: cstring, uid, gid: U32): U64 =
  let req = queueFsRequest(SysFsOpChown, path, nil, U64(uid), U64(gid))
  if req == nil:
    if not canFallbackToRawFs():
      return U64(-1'i64)

    return U64(rawChownKernel(path, uid, gid))

  let resp = waitFsResponse(req)
  let outValue =
    if resp == nil:
      U64(-1'i64)
    else:
      U64(resp.result)

  finishPending(req)
  outValue

