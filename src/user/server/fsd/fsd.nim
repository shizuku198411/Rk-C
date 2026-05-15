import ../../lib/core/io
import ../../lib/core/syscall
import ../lib/service_ready

var
  req: SysFsRequest
  resp: SysFsResponse


proc reqPath(): cstring =
  cast[cstring](addr req.path[0])


proc clearResponse() =
  resp = SysFsResponse()
  resp.id = req.id


proc handleLs() =
  let maxEntries = req.capacity div U64(sizeof(DirEntry))
  resp.result = sysRawLs(reqPath(), addr resp.data[0], maxEntries)
  if resp.result > 0:
    resp.size = U64(resp.result) * U64(sizeof(DirEntry))


proc handleMkdir() =
  resp.result = sysRawMkdir(reqPath())


proc handleUnlink() =
  resp.result = sysRawUnlink(reqPath())


proc handleRmdir() =
  resp.result = sysRawRmdir(reqPath())


proc handleReadFile() =
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

  if sysFsServiceRegister() != 0:
    write("fsd: register failed\n")
    sysExit(1)

  notifyServiceReady(SysServiceKindFs)

  while true:
    if sysFsServiceReceive(addr req) < 0:
      write("fsd: receive failed\n")
      sysExit(1)

    handleRequest()
