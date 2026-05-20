import ../../../lib/fixed_string
import ../../../lib/mem
import ../../../lib/syscall_types
import ../../../lib/types
import ../../fs/dirent
import ../../fs/fs
import ../../mm/usercopy
import ../../service/registry
import ../ipc/request_reply
import ../syscall_cap
import ../../task/process

const
  FsPendingMax = 8
  FsRawDirEntryMax = 32

type
  PendingFsRequest = object
    ipc: IpcPending
    request: SysFsRequest
    response: SysFsResponse

var
  requestDomain: IpcRequestDomain
  pending: array[FsPendingMax, PendingFsRequest]
  rawEntries: array[FsRawDirEntryMax, FsDirEntry]
  rawFileBuf: array[SysFsDataMax, U8]
  renamePathBuf: array[SysFsPathMax, char]


proc allocPending(): ptr PendingFsRequest =
  allocIpcPending(pending)


proc findPending(id: U64): ptr PendingFsRequest =
  findIpcPending(pending, id)


proc queueFsRequest(op: U32, path: cstring, data: pointer, size, capacity: U64): ptr PendingFsRequest =
  if not fsServiceAvailable() or currentIsFsService():
    return nil
  if capacity > SysFsDataMax:
    return nil
  if data != nil and size > SysFsDataMax:
    return nil

  let p = allocPending()
  if p == nil:
    return nil

  p.request.id = assignIpcRequestId(requestDomain, addr p.ipc)
  p.request.op = op
  if currentProc != nil:
    p.request.uid = currentProc.identity.uid
    p.request.gid = currentProc.identity.gid
  p.request.size = size
  p.request.capacity = capacity
  discard copyCString(p.request.path, path)

  if data != nil and size > 0:
    discard copyMem(addr p.request.data[0], data, size)

  wakeIpcWaiter(servicePid(serviceFs))
  p


proc waitFsResponse(p: ptr PendingFsRequest): ptr SysFsResponse =
  if not waitIpcReply(addr p.ipc, serviceFs, waitFsReq):
    return nil

  addr p.response


proc finishPending(p: ptr PendingFsRequest) =
  finishIpcPending(p)


proc rawLsKernel(path: cstring, outEntries: ptr FsDirEntry, maxEntries: U64, offset: U64 = 0): int =
  if outEntries == nil or maxEntries == 0:
    return -1

  let entries = cast[ptr UncheckedArray[FsDirEntry]](outEntries)
  var count = U64(0)
  while count < maxEntries:
    let readResult = fsReadDirEntry(path, offset + count, addr entries[count])
    if readResult < 0:
      if count == 0:
        return -1
      return int(count)
    if readResult == 0:
      return int(count)
    inc count

  int(count)


proc rawReadFileKernel(path: cstring, buf: pointer, capacity: U64): int =
  fsReadFile(path, buf, capacity)


proc rawFileSizeKernel(path: cstring): int =
  fsFileSize(path)


proc rawReadFileRangeKernel(path: cstring, buf: pointer, offset, capacity: U64): int =
  fsReadFileRange(path, buf, offset, capacity)


proc rawRenameKernel(oldPath, newPath: cstring): int =
  fsRename(oldPath, newPath)


proc rawChmodKernel(path: cstring, mode: U32): int =
  fsChmod(path, mode)


proc rawChownKernel(path: cstring, uid, gid: U32): int =
  fsChown(path, uid, gid)


proc unpackWriteSizeFlags(value: U64, size: var U64, flags: var U32) =
  size = value and U64(0xffffffff'u64)
  flags = U32(value shr U64(32))
  if flags == U32(0):
    flags = SysFsWriteDefault


proc unpackLsLimitOffset(value: U64, maxEntries: var U64, offset: var U64) =
  maxEntries = value and U64(0xffffffff'u64)
  offset = value shr U64(32)


proc syscallFsInfo*(outEntriesVal, maxEntriesVal: U64): U64 =
  if outEntriesVal == 0 or maxEntriesVal == 0:
    return U64(-1'i64)

  let maxEntries =
    if maxEntriesVal > U64(SysFsInfoMaxEntries):
      U64(SysFsInfoMaxEntries)
    else:
      maxEntriesVal

  var entries: array[SysFsInfoMaxEntries, SysFsInfoEntry]
  let count = fsInfo(addr entries[0], maxEntries)
  if count < 0:
    return U64(-1'i64)

  let bytes = U64(count) * U64(sizeof(SysFsInfoEntry))
  if copyToUser(outEntriesVal, addr entries[0], bytes) != 0:
    return U64(-1'i64)

  U64(count)


proc syscallFsServiceRegister*(): U64 =
  if currentIsFsService():
    return 0
  if not canSyscallFsServiceRegister():
    return U64(-1'i64)

  registerService(serviceFs, currentProc.pid)
  0


proc syscallFsServiceReceive*(outReq: U64): U64 =
  if outReq == 0 or not canSyscallFsServiceReceive():
    return U64(-1'i64)

  while true:
    var i = 0
    while i < FsPendingMax:
      if pending[i].ipc.used and not pending[i].ipc.completed:
        if copyToUser(outReq, addr pending[i].request, U64(sizeof(SysFsRequest))) != 0:
          return U64(-1'i64)

        return pending[i].request.id
      inc i

    sleepCurrentForIpc()


proc syscallFsServiceReply*(respVal: U64): U64 =
  if respVal == 0 or not canSyscallFsServiceReply():
    return U64(-1'i64)

  var resp: SysFsResponse
  if copyFromUser(addr resp, respVal, U64(sizeof(SysFsResponse))) != 0:
    return U64(-1'i64)

  let p = findPending(resp.id)
  if p == nil:
    return U64(-1'i64)

  p.response = resp
  p.ipc.completed = true
  wakeFsWaiter(resp.id)
  0


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


proc syscallRawLs*(pathVal, entriesVal, maxEntriesVal: U64): U64 =
  var maxEntries: U64
  var offset: U64
  unpackLsLimitOffset(maxEntriesVal, maxEntries, offset)

  if not canSyscallRawFs() or pathVal == 0 or entriesVal == 0 or maxEntries == 0:
    return U64(-1'i64)

  var pathBuf: array[SysFsPathMax, char]
  if copyUserCString(addr pathBuf[0], pathVal, U64(SysFsPathMax)) < 0:
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


proc syscallRawMkdir*(pathVal: U64): U64 =
  if not canSyscallRawFs() or pathVal == 0:
    return U64(-1'i64)

  var pathBuf: array[SysFsPathMax, char]
  if copyUserCString(addr pathBuf[0], pathVal, U64(SysFsPathMax)) < 0:
    return U64(-1'i64)

  U64(fsMkdir(cast[cstring](addr pathBuf[0])))


proc syscallRawUnlink*(pathVal: U64): U64 =
  if not canSyscallRawFs() or pathVal == 0:
    return U64(-1'i64)

  var pathBuf: array[SysFsPathMax, char]
  if copyUserCString(addr pathBuf[0], pathVal, U64(SysFsPathMax)) < 0:
    return U64(-1'i64)

  U64(fsUnlink(cast[cstring](addr pathBuf[0])))


proc syscallRawRmdir*(pathVal: U64): U64 =
  if not canSyscallRawFs() or pathVal == 0:
    return U64(-1'i64)

  var pathBuf: array[SysFsPathMax, char]
  if copyUserCString(addr pathBuf[0], pathVal, U64(SysFsPathMax)) < 0:
    return U64(-1'i64)

  U64(fsRmdir(cast[cstring](addr pathBuf[0])))


proc syscallRawReadFile*(pathVal, bufVal, capacity: U64): U64 =
  if not canSyscallRawFs() or pathVal == 0 or bufVal == 0 or capacity > SysFsDataMax:
    return U64(-1'i64)

  var pathBuf: array[SysFsPathMax, char]
  if copyUserCString(addr pathBuf[0], pathVal, U64(SysFsPathMax)) < 0:
    return U64(-1'i64)

  let readLen = rawReadFileKernel(cast[cstring](addr pathBuf[0]), addr rawFileBuf[0], capacity)
  if readLen < 0:
    return U64(-1'i64)
  if copyToUser(bufVal, addr rawFileBuf[0], U64(readLen)) != 0:
    return U64(-1'i64)

  U64(readLen)


proc syscallRawFileSize*(pathVal: U64): U64 =
  if not canSyscallRawFs() or pathVal == 0:
    return U64(-1'i64)

  var pathBuf: array[SysFsPathMax, char]
  if copyUserCString(addr pathBuf[0], pathVal, U64(SysFsPathMax)) < 0:
    return U64(-1'i64)

  let size = rawFileSizeKernel(cast[cstring](addr pathBuf[0]))
  if size < 0:
    return U64(-1'i64)

  U64(size)


proc syscallRawReadRange*(reqVal: U64): U64 =
  if not canSyscallRawFs() or reqVal == 0:
    return U64(-1'i64)

  var req: SysFsRequest
  if copyFromUser(addr req, reqVal, U64(sizeof(SysFsRequest))) != 0:
    return U64(-1'i64)
  if req.capacity > SysFsDataMax:
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


proc syscallRawWriteFile*(pathVal, bufVal, sizeFlags: U64): U64 =
  var size: U64
  var flags: U32
  unpackWriteSizeFlags(sizeFlags, size, flags)

  if not canSyscallRawFs() or pathVal == 0 or size > SysFsDataMax:
    return U64(-1'i64)

  var pathBuf: array[SysFsPathMax, char]
  if copyUserCString(addr pathBuf[0], pathVal, U64(SysFsPathMax)) < 0:
    return U64(-1'i64)
  if copyFromUser(addr rawFileBuf[0], bufVal, size) != 0:
    return U64(-1'i64)

  U64(fsWriteFileWithFlags(cast[cstring](addr pathBuf[0]), addr rawFileBuf[0], size, flags))


proc syscallRawRename*(oldPathVal, newPathVal: U64): U64 =
  if not canSyscallRawFs() or oldPathVal == 0 or newPathVal == 0:
    return U64(-1'i64)

  var oldPathBuf: array[SysFsPathMax, char]
  var newPathBuf: array[SysFsPathMax, char]
  if copyUserCString(addr oldPathBuf[0], oldPathVal, U64(SysFsPathMax)) < 0:
    return U64(-1'i64)
  if copyUserCString(addr newPathBuf[0], newPathVal, U64(SysFsPathMax)) < 0:
    return U64(-1'i64)

  U64(rawRenameKernel(cast[cstring](addr oldPathBuf[0]), cast[cstring](addr newPathBuf[0])))


proc syscallRawChmod*(pathVal, modeVal: U64): U64 =
  if not canSyscallRawFs() or pathVal == 0:
    return U64(-1'i64)

  var pathBuf: array[SysFsPathMax, char]
  if copyUserCString(addr pathBuf[0], pathVal, U64(SysFsPathMax)) < 0:
    return U64(-1'i64)

  U64(rawChmodKernel(cast[cstring](addr pathBuf[0]), U32(modeVal)))


proc syscallRawChown*(pathVal, uidGidVal: U64): U64 =
  if not canSyscallRawFs() or pathVal == 0:
    return U64(-1'i64)

  var pathBuf: array[SysFsPathMax, char]
  if copyUserCString(addr pathBuf[0], pathVal, U64(SysFsPathMax)) < 0:
    return U64(-1'i64)

  let uid = U32(uidGidVal and U64(0xffffffff'u64))
  let gid = U32(uidGidVal shr U64(32))
  U64(rawChownKernel(cast[cstring](addr pathBuf[0]), uid, gid))
