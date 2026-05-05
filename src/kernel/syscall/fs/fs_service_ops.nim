import ../../../lib/mem
import ../../../lib/syscall_types
import ../../../lib/types
import ../../fs/dirent
import ../../fs/fs
import ../../mm/usercopy
import ../../task/process

const
  FsPendingMax = 8
  FsRawDirEntryMax = 32

type
  PendingFsRequest = object
    used: bool
    completed: bool
    request: SysFsRequest
    response: SysFsResponse

var
  fsServerPid: int32
  fsServerRegistered: bool
  nextReqId = U64(1)
  pending: array[FsPendingMax, PendingFsRequest]
  rawEntries: array[FsRawDirEntryMax, FsDirEntry]
  rawFileBuf: array[SysFsDataMax, U8]


proc currentIsFsServer(): bool =
  currentProc != nil and fsServerPid != 0 and currentProc.pid == fsServerPid


proc isFsServicePid*(pid: int32): bool =
  fsServerRegistered and fsServerPid == pid


proc fsServerAvailable(): bool =
  let p = findProcessByPid(fsServerPid)
  p != nil and p.state != procZombie and p.state != procUnused


proc canFallbackToRawFs(): bool =
  not fsServerRegistered or currentIsFsServer()


proc copyPath(dst: var array[SysFsPathMax, char], src: cstring) =
  var i = 0
  while i < SysFsPathMax - 1 and src != nil and src[i] != '\0':
    dst[i] = src[i]
    inc i

  while i < SysFsPathMax:
    dst[i] = '\0'
    inc i


proc allocPending(): ptr PendingFsRequest =
  var i = 0
  while i < FsPendingMax:
    if not pending[i].used:
      pending[i] = PendingFsRequest()
      pending[i].used = true
      return addr pending[i]
    inc i

  nil


proc findPending(id: U64): ptr PendingFsRequest =
  var i = 0
  while i < FsPendingMax:
    if pending[i].used and pending[i].request.id == id:
      return addr pending[i]
    inc i

  nil


proc queueFsRequest(op: U32, path: cstring, data: pointer, size, capacity: U64): ptr PendingFsRequest =
  if not fsServerAvailable() or currentIsFsServer():
    return nil
  if size > SysFsDataMax or capacity > SysFsDataMax:
    return nil

  let p = allocPending()
  if p == nil:
    return nil

  p.request.id = nextReqId
  inc nextReqId
  p.request.op = op
  p.request.size = size
  p.request.capacity = capacity
  copyPath(p.request.path, path)

  if size > 0:
    discard copyMem(addr p.request.data[0], data, size)

  wakeIpcWaiter(fsServerPid)
  p


proc waitFsResponse(p: ptr PendingFsRequest): ptr SysFsResponse =
  while p.used and not p.completed:
    if not fsServerAvailable():
      return nil

    sleepCurrentForFsReq(p.request.id)

  if not p.used:
    return nil

  addr p.response


proc finishPending(p: ptr PendingFsRequest) =
  if p != nil:
    p[] = PendingFsRequest()


proc rawLsKernel(path: cstring, outEntries: ptr FsDirEntry, maxEntries: U64): int =
  fsReadDirEntries(path, outEntries, maxEntries)


proc rawReadFileKernel(path: cstring, buf: pointer, capacity: U64): int =
  fsReadFile(path, buf, capacity)


proc syscallFsServiceRegister*(): U64 =
  if currentProc == nil or not currentProc.isUser:
    return U64(-1'i64)

  fsServerPid = currentProc.pid
  fsServerRegistered = true
  0


proc syscallFsServiceReceive*(outReq: U64): U64 =
  if outReq == 0 or not currentIsFsServer():
    return U64(-1'i64)

  while true:
    var i = 0
    while i < FsPendingMax:
      if pending[i].used and not pending[i].completed:
        if copyToUser(outReq, addr pending[i].request, U64(sizeof(SysFsRequest))) != 0:
          return U64(-1'i64)

        return pending[i].request.id
      inc i

    sleepCurrentForIpc()


proc syscallFsServiceReply*(respVal: U64): U64 =
  if respVal == 0 or not currentIsFsServer():
    return U64(-1'i64)

  var resp: SysFsResponse
  if copyFromUser(addr resp, respVal, U64(sizeof(SysFsResponse))) != 0:
    return U64(-1'i64)

  let p = findPending(resp.id)
  if p == nil:
    return U64(-1'i64)

  p.response = resp
  p.completed = true
  wakeFsWaiter(resp.id)
  0


proc serviceLs*(path: cstring, entriesVal, maxEntries: U64): U64 =
  let entryBytes = maxEntries * U64(sizeof(FsDirEntry))
  let req = queueFsRequest(SysFsOpLs, path, nil, 0, entryBytes)
  if req == nil:
    if not canFallbackToRawFs():
      return U64(-1'i64)

    let rawMax =
      if maxEntries > U64(FsRawDirEntryMax):
        U64(FsRawDirEntryMax)
      else:
        maxEntries
    let count = rawLsKernel(path, addr rawEntries[0], rawMax)
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


proc serviceMkdir*(path: cstring): U64 =
  let req = queueFsRequest(SysFsOpMkdir, path, nil, 0, 0)
  if req == nil:
    if not canFallbackToRawFs():
      return U64(-1'i64)

    return U64(fsMkdir(path))

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


proc serviceWriteFile*(path: cstring, data: pointer, size: U64): U64 =
  let req = queueFsRequest(SysFsOpWriteFile, path, data, size, 0)
  if req == nil:
    if not canFallbackToRawFs():
      return U64(-1'i64)

    return U64(fsWriteFile(path, data, size))

  let resp = waitFsResponse(req)
  let outValue =
    if resp == nil:
      U64(-1'i64)
    else:
      U64(resp.result)

  finishPending(req)
  outValue


proc syscallRawLs*(pathVal, entriesVal, maxEntries: U64): U64 =
  if not currentIsFsServer() or pathVal == 0 or entriesVal == 0:
    return U64(-1'i64)

  var pathBuf: array[SysFsPathMax, char]
  if copyUserCString(addr pathBuf[0], pathVal, U64(SysFsPathMax)) < 0:
    return U64(-1'i64)

  let countMax =
    if maxEntries > U64(FsRawDirEntryMax):
      U64(FsRawDirEntryMax)
    else:
      maxEntries
  let count = rawLsKernel(cast[cstring](addr pathBuf[0]), addr rawEntries[0], countMax)
  if count < 0:
    return U64(-1'i64)

  let bytes = U64(count) * U64(sizeof(FsDirEntry))
  if copyToUser(entriesVal, addr rawEntries[0], bytes) != 0:
    return U64(-1'i64)

  U64(count)


proc syscallRawMkdir*(pathVal: U64): U64 =
  if not currentIsFsServer() or pathVal == 0:
    return U64(-1'i64)

  var pathBuf: array[SysFsPathMax, char]
  if copyUserCString(addr pathBuf[0], pathVal, U64(SysFsPathMax)) < 0:
    return U64(-1'i64)

  U64(fsMkdir(cast[cstring](addr pathBuf[0])))


proc syscallRawUnlink*(pathVal: U64): U64 =
  if not currentIsFsServer() or pathVal == 0:
    return U64(-1'i64)

  var pathBuf: array[SysFsPathMax, char]
  if copyUserCString(addr pathBuf[0], pathVal, U64(SysFsPathMax)) < 0:
    return U64(-1'i64)

  U64(fsUnlink(cast[cstring](addr pathBuf[0])))


proc syscallRawRmdir*(pathVal: U64): U64 =
  if not currentIsFsServer() or pathVal == 0:
    return U64(-1'i64)

  var pathBuf: array[SysFsPathMax, char]
  if copyUserCString(addr pathBuf[0], pathVal, U64(SysFsPathMax)) < 0:
    return U64(-1'i64)

  U64(fsRmdir(cast[cstring](addr pathBuf[0])))


proc syscallRawReadFile*(pathVal, bufVal, capacity: U64): U64 =
  if not currentIsFsServer() or pathVal == 0 or bufVal == 0 or capacity > SysFsDataMax:
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


proc syscallRawWriteFile*(pathVal, bufVal, size: U64): U64 =
  if not currentIsFsServer() or pathVal == 0 or size > SysFsDataMax:
    return U64(-1'i64)

  var pathBuf: array[SysFsPathMax, char]
  if copyUserCString(addr pathBuf[0], pathVal, U64(SysFsPathMax)) < 0:
    return U64(-1'i64)
  if copyFromUser(addr rawFileBuf[0], bufVal, size) != 0:
    return U64(-1'i64)

  U64(fsWriteFile(cast[cstring](addr pathBuf[0]), addr rawFileBuf[0], size))
