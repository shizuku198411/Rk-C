import ../../lib/core/io
import ../../lib/core/syscall
import ../../lib/ipc/service_client
import ../lib/service_ready


var
  req: SysFsRequest
  resp: SysFsResponse
  rawReq: SysFsRequest

  procPacket: SysIpcPacket
  procResp: SysIpcPacket


proc reqPath(): cstring =
  cast[cstring](addr req.path[0])


proc reqDataPath(): cstring =
  cast[cstring](addr req.data[0])


proc clearResponse() =
  resp = SysFsResponse()
  resp.id = req.id


proc isProcPath(path: cstring): bool =
  path[0] == '/' and
  path[1] == 'p' and
  path[2] == 'r' and
  path[3] == 'o' and
  path[4] == 'c' and
  (path[5] == '\0' or path[5] == '/')


proc isRootPath(path: cstring): bool =
  path[0] == '/' and path[1] == '\0'


proc copyPathToPacket(packet: var SysIpcPacket, path: cstring) =
  var i = U32(0)
  while i + U32(1) < SysIpcMessageMax and path[i] != '\0':
    packet.data[i] = path[i]
    inc i
  
  packet.data[i] = '\0'
  packet.len = i


proc copyPathToFsRequest(outReq: var SysFsRequest, path: cstring) =
  var i = U32(0)
  while i + U32(1) < SysFsPathMax and path[i] != '\0':
    outReq.path[i] = path[i]
    inc i

  outReq.path[i] = '\0'


proc requestProcFs(op: U32, path: cstring, capacity: U64, offset: U64 = 0): I32 =
  let pid = servicePidByKind(SysServiceKindProcFs)
  if pid <= 0:
    return -1

  procPacket = SysIpcPacket()
  procPacket.op = op
  procPacket.arg0 = capacity
  procPacket.arg1 = offset
  copyPathToPacket(procPacket, path)

  if sysIpcSendPacket(pid, addr procPacket) < 0:
    return -1

  while true:
    if sysIpcReceivePacket(addr procResp) < 0:
      return -1

    if procResp.senderPid == pid:
      if op == SysIpcOpProcFsReadRequest and procResp.op == SysIpcOpProcFsReadResponse:
        return I32(procResp.arg0)
      if op == SysIpcOpProcFsLsRequest and procResp.op == SysIpcOpProcFsLsResponse:
        return I32(procResp.arg0)


proc writeDirEntry(entry: ptr DirEntry, name: cstring, typ: U32) =
  entry.typ = typ
  entry.size = 0
  entry.uid = 0
  entry.gid = 0
  entry.mode = 0o555

  var i = 0
  while i + 1 < DirEntryNameMax and name[i] != '\0':
    entry.name[i] = name[i]
    inc i
  
  entry.name[i] = '\0'


proc handleProcLs() =
  let entrySize = U64(sizeof(DirEntry))
  let requestedEntries = req.capacity div entrySize
  let procChunkEntries = U64(SysIpcMessageMax) div entrySize
  if requestedEntries == U64(0) or procChunkEntries == U64(0):
    resp.result = 0
    resp.size = 0
    return

  var total = U64(0)
  var done = false
  while total < requestedEntries and not done:
    var chunkEntries = requestedEntries - total
    if chunkEntries > procChunkEntries:
      chunkEntries = procChunkEntries

    let count = requestProcFs(
      SysIpcOpProcFsLsRequest,
      reqPath(),
      chunkEntries * entrySize,
      req.size + total,
    )
    if count < 0:
      resp.result = -1
      resp.size = 0
      return

    if count == 0:
      done = true
    else:
      var copySize = U64(count) * entrySize
      if copySize > U64(procResp.len):
        copySize = U64(procResp.len)
      if total * entrySize + copySize > SysFsDataMax:
        copySize = SysFsDataMax - total * entrySize

      var i = U64(0)
      let dstBase = total * entrySize
      while i < copySize:
        resp.data[dstBase + i] = U8(procResp.data[i])
        inc i

      total += U64(count)
      if U64(count) < chunkEntries:
        done = true

  resp.result = I32(total)
  resp.size = total * entrySize


proc handleLs() =
  if isProcPath(reqPath()):
    if reqPath()[0] == '/' and reqPath()[1] == 'p':
      handleProcLs()
      return

  let maxEntries = req.capacity div U64(sizeof(DirEntry))
  if isRootPath(reqPath()):
    let rawTotal = sysRawLsAt(reqPath(), addr resp.data[0], U64(32), U64(0))
    if rawTotal < 0:
      resp.result = -1
      return

    if req.size < U64(rawTotal):
      resp.result = sysRawLsAt(reqPath(), addr resp.data[0], maxEntries, req.size)
      if resp.result < 0:
        return

      var count = U64(resp.result)
      if count < maxEntries and req.size + count == U64(rawTotal):
        let outBuf = cast[ptr UncheckedArray[DirEntry]](addr resp.data[0])
        writeDirEntry(addr outBuf[count], cstring"proc", DirEntryTypeMount)
        inc count
        resp.result = I32(count)
      resp.size = count * U64(sizeof(DirEntry))
      return

    if req.size == U64(rawTotal) and maxEntries > U64(0):
      let outBuf = cast[ptr UncheckedArray[DirEntry]](addr resp.data[0])
      writeDirEntry(addr outBuf[0], cstring"proc", DirEntryTypeMount)
      resp.result = 1
      resp.size = U64(sizeof(DirEntry))
      return

    resp.result = 0
    resp.size = 0
    return

  resp.result = sysRawLsAt(reqPath(), addr resp.data[0], maxEntries, req.size)
  if resp.result >= 0:
    resp.size = U64(resp.result) * U64(sizeof(DirEntry))


proc handleMkdir() =
  resp.result = sysRawMkdir(reqPath())
  if resp.result == 0 and sysRawChown(reqPath(), req.uid, req.gid) < 0:
    discard sysRawRmdir(reqPath())
    resp.result = -1


proc handleUnlink() =
  resp.result = sysRawUnlink(reqPath())


proc handleRmdir() =
  resp.result = sysRawRmdir(reqPath())


proc handleReadFile() =
  if isProcPath(reqPath()):
    let n = requestProcFs(SysIpcOpProcFsReadRequest, reqPath(), req.capacity)
    if n < 0:
      resp.result = -1
      return

    var copySize = U64(n)
    if copySize > req.capacity:
      copySize = req.capacity
    if copySize > SysFsDataMax:
      copySize = SysFsDataMax

    resp.result = I32(copySize)
    resp.size = copySize

    var i = U64(0)
    while i < copySize:
      resp.data[i] = U8(procResp.data[i])
      inc i

    return

  resp.result = sysRawReadFile(reqPath(), addr resp.data[0], req.capacity)
  if resp.result > 0:
    resp.size = U64(resp.result)


proc handleFileSize() =
  if isProcPath(reqPath()):
    resp.result = requestProcFs(SysIpcOpProcFsReadRequest, reqPath(), SysFsDataMax)
    return

  resp.result = sysRawFileSize(reqPath())


proc handleReadRange() =
  if isProcPath(reqPath()):
    var requestCapacity = req.size + req.capacity
    if requestCapacity > SysFsDataMax:
      requestCapacity = SysFsDataMax

    let n = requestProcFs(SysIpcOpProcFsReadRequest, reqPath(), requestCapacity)
    if n < 0:
      resp.result = -1
      return
    if req.size >= U64(n):
      resp.result = 0
      resp.size = 0
      return

    var copySize = U64(n) - req.size
    if copySize > req.capacity:
      copySize = req.capacity
    if copySize > SysFsDataMax:
      copySize = SysFsDataMax

    resp.result = I32(copySize)
    resp.size = copySize

    var i = U64(0)
    while i < copySize:
      resp.data[i] = U8(procResp.data[req.size + i])
      inc i

    return

  rawReq = SysFsRequest()
  rawReq.size = req.size
  rawReq.capacity = req.capacity
  copyPathToFsRequest(rawReq, reqPath())

  resp.result = sysRawReadRange(addr rawReq)
  if resp.result > 0:
    resp.size = U64(resp.result)

    var i = U64(0)
    while i < resp.size and i < SysFsDataMax:
      resp.data[i] = rawReq.data[i]
      inc i


proc handleWriteFile() =
  let created = sysRawFileSize(reqPath()) < 0
  resp.result = sysRawWriteFileMode(reqPath(), addr req.data[0], req.size, U32(req.capacity))
  if resp.result == 0 and created and sysRawChown(reqPath(), req.uid, req.gid) < 0:
    discard sysRawUnlink(reqPath())
    resp.result = -1


## Forwards a chunked file write while preserving the requested file offset.
proc handleWriteRange() =
  rawReq = SysFsRequest()
  rawReq.size = req.size
  rawReq.capacity = req.capacity
  copyPathToFsRequest(rawReq, reqPath())

  var i = U64(0)
  while i < req.size and i < SysFsDataMax:
    rawReq.data[i] = req.data[i]
    inc i

  resp.result = sysRawWriteRange(addr rawReq)


proc handleRename() =
  if isProcPath(reqPath()) or isProcPath(reqDataPath()):
    resp.result = -1
    return

  resp.result = sysRawRename(reqPath(), reqDataPath())


proc handleChmod() =
  if isProcPath(reqPath()):
    resp.result = -1
    return

  resp.result = sysRawChmod(reqPath(), U32(req.size))


proc handleChown() =
  if isProcPath(reqPath()):
    resp.result = -1
    return

  resp.result = sysRawChown(reqPath(), U32(req.size), U32(req.capacity))


proc handleRequest() =
  clearResponse()

  if req.op == SysFsOpLs:
    handleLs()
  elif req.op == SysFsOpMkdir:
    handleMkdir()
  elif req.op == SysFsOpUnlink:
    handleUnlink()
  elif req.op == SysFsOpRmdir:
    handleRmdir()
  elif req.op == SysFsOpReadFile:
    handleReadFile()
  elif req.op == SysFsOpWriteFile:
    handleWriteFile()
  elif req.op == SysFsOpRename:
    handleRename()
  elif req.op == SysFsOpChmod:
    handleChmod()
  elif req.op == SysFsOpChown:
    handleChown()
  elif req.op == SysFsOpFileSize:
    handleFileSize()
  elif req.op == SysFsOpReadRange:
    handleReadRange()
  elif req.op == SysFsOpWriteRange:
    handleWriteRange()
  else:
    resp.result = -1

  discard sysFsServiceReply(addr resp)


proc user_start*(arg: cstring) {.exportc, cdecl, noreturn.} =
  discard arg

  if not waitUntilServiceRegistered(SysServiceKindFs):
    write("[fsd] service registration timeout\n")
    sysExit(1)

  notifyServiceReady(SysServiceKindFs)

  while true:
    if sysFsServiceReceive(addr req) < 0:
      write("fsd: receive failed\n")
      sysExit(1)

    handleRequest()
