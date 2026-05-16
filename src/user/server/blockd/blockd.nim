import ../../lib/core/io
import ../../lib/core/syscall
import ../lib/service_ready

var
  req: SysBlockRequest
  resp: SysBlockResponse


proc clearResponse() =
  resp = SysBlockResponse()
  resp.id = req.id


proc handleRead() =
  resp.result = sysRawBlockRead(req.blockIndex, addr resp.data[0])


proc handleWrite() =
  resp.result = sysRawBlockWrite(req.blockIndex, addr req.data[0])


proc handleRequest() =
  clearResponse()

  if req.op == SysBlockOpRead:
    handleRead()
  elif req.op == SysBlockOpWrite:
    handleWrite()
  else:
    resp.result = -1

  discard sysBlockServiceReply(addr resp)


proc user_start*(arg: cstring) {.exportc, cdecl, noreturn.} =
  discard arg

  if not waitUntilServiceRegistered(SysServiceKindBlock):
    write("[blockd] service registration timeout\n")
    sysExit(1)

  notifyServiceReady(SysServiceKindBlock)

  while true:
    if sysBlockServiceReceive(addr req) < 0:
      write("blockd: receive failed\n")
      sysExit(1)

    handleRequest()
