## Manages filesystem service request queues and registration syscalls.

## Allocates pending.
proc allocPending(): ptr PendingFsRequest =
  allocIpcPending(pending)


## Finds pending.
proc findPending(id: U64): ptr PendingFsRequest =
  findIpcPending(pending, id)


## Queues fs request.
proc queueFsRequest(op: U32, path: cstring, data: pointer, size, capacity: U64): ptr PendingFsRequest =
  if not fsServiceAvailable() or currentIsFsService():
    return nil
  if op != SysFsOpWriteRange and capacity > SysFsDataMax:
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


## Waits for fs response.
proc waitFsResponse(p: ptr PendingFsRequest): ptr SysFsResponse =
  if not waitIpcReply(addr p.ipc, serviceFs, waitFsReq):
    return nil

  addr p.response


## Finishes pending.
proc finishPending(p: ptr PendingFsRequest) =
  finishIpcPending(p)


## Implements the raw ls kernel kernel helper.
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


## Implements the raw read file kernel kernel helper.
proc rawReadFileKernel(path: cstring, buf: pointer, capacity: U64): int =
  fsReadFile(path, buf, capacity)


## Implements the raw file size kernel kernel helper.
proc rawFileSizeKernel(path: cstring): int =
  fsFileSize(path)


## Implements the raw read file range kernel kernel helper.
proc rawReadFileRangeKernel(path: cstring, buf: pointer, offset, capacity: U64): int =
  fsReadFileRange(path, buf, offset, capacity)


## Implements the raw write file range kernel helper.
proc rawWriteFileRangeKernel(path: cstring, buf: pointer, offset, size: U64): int =
  fsWriteFileRange(path, buf, offset, size)


## Implements the raw rename kernel kernel helper.
proc rawRenameKernel(oldPath, newPath: cstring): int =
  fsRename(oldPath, newPath)


## Implements the raw chmod kernel kernel helper.
proc rawChmodKernel(path: cstring, mode: U32): int =
  fsChmod(path, mode)


## Implements the raw chown kernel kernel helper.
proc rawChownKernel(path: cstring, uid, gid: U32): int =
  fsChown(path, uid, gid)


## Implements the unpack write size flags kernel helper.
proc unpackWriteSizeFlags(value: U64, size: var U64, flags: var U32) =
  size = value and U64(0xffffffff'u64)
  flags = U32(value shr U64(32))
  if flags == U32(0):
    flags = SysFsWriteDefault


## Implements the unpack ls limit offset kernel helper.
proc unpackLsLimitOffset(value: U64, maxEntries: var U64, offset: var U64) =
  maxEntries = value and U64(0xffffffff'u64)
  offset = value shr U64(32)


## Handles the fs info syscall operation.
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


## Handles the fs service register syscall operation.
proc syscallFsServiceRegister*(): U64 =
  if currentIsFsService():
    return 0
  if not canSyscallFsServiceRegister():
    return U64(-1'i64)

  registerService(serviceFs, currentProc.pid)
  0


## Handles the fs service receive syscall operation.
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


## Handles the fs service reply syscall operation.
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
