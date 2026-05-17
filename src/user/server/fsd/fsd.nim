import ../../lib/core/io
import ../../lib/core/syscall
import ../../lib/ipc/service_client
import ../lib/service_ready


var
  req: SysFsRequest
  resp: SysFsResponse

  procPacket: SysIpcPacket
  procResp: SysIpcPacket


proc reqPath(): cstring =
  cast[cstring](addr req.path[0])


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


proc requestProcFs(op: U32, path: cstring, capacity: U64): I32 =
  let pid = servicePidByKind(SysServiceKindProcFs)
  if pid <= 0:
    return -1

  procPacket = SysIpcPacket()
  procPacket.op = op
  procPacket.arg0 = capacity
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

  var i = 0
  while i + 1 < DirEntryNameMax and name[i] != '\0':
    entry.name[i] = name[i]
    inc i
  
  entry.name[i] = '\0'


proc handleProcLs() =
  let count = requestProcFs(SysIpcOpProcFsLsRequest, reqPath(), req.capacity)
  if count < 0:
    resp.result = -1
    return

  resp.result = count
  resp.size = procResp.len

  var i = U32(0)
  while i < procResp.len and i < SysFsDataMax:
    resp.data[i] = U8(procResp.data[i])
    inc i


proc handleLs() =
  if isProcPath(reqPath()):
    if reqPath()[0] == '/' and reqPath()[1] == 'p':
      handleProcLs()
      return

  let maxEntries = req.capacity div U64(sizeof(DirEntry))
  resp.result = sysRawLs(reqPath(), addr resp.data[0], maxEntries)
  if resp.result >= 0:
    var count = U64(resp.result)
    if isRootPath(reqPath()) and count < maxEntries:
      let outBuf = cast[ptr UncheckedArray[DirEntry]](addr resp.data[0])
      writeDirEntry(addr outBuf[count], cstring"proc", DirEntryTypeMount)
      count += 1.U64
      resp.result = I32(count)
    resp.size = count * U64(sizeof(DirEntry))


proc handleMkdir() =
  resp.result = sysRawMkdir(reqPath())


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


proc handleWriteFile() =
  resp.result = sysRawWriteFile(reqPath(), addr req.data[0], req.size)


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
