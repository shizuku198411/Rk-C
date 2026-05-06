import ../../../lib/mem
import ../../../lib/syscall_types
import ../../../lib/types
import ../../fs/blockdev
import ../../mm/usercopy
import ../../service/registry
import ../ipc/request_reply
import ../../task/process

const
  BlockPendingMax = 8
  BlockSize* = blockdev.BlockSize

type
  PendingBlockRequest = object
    ipc: IpcPending
    request: SysBlockRequest
    response: SysBlockResponse

var
  requestDomain: IpcRequestDomain
  pending: array[BlockPendingMax, PendingBlockRequest]
  rawBlockBuf: array[SysBlockDataSize, U8]


proc blockServiceInit*() =
  blockdevInit()


proc currentIsBlockServer(): bool =
  currentIsService(serviceBlock)


proc blockServerAvailable(): bool =
  serviceAvailable(serviceBlock)


proc canFallbackToRawBlock(): bool =
  not serviceRegistered(serviceBlock) or currentIsBlockServer()


proc allocPending(): ptr PendingBlockRequest =
  allocIpcPending(pending)


proc findPending(id: U64): ptr PendingBlockRequest =
  findIpcPending(pending, id)


proc queueBlockRequest(op: U32, blockIndex: U64, data: pointer): ptr PendingBlockRequest =
  if not blockServerAvailable() or currentIsBlockServer():
    return nil

  let p = allocPending()
  if p == nil:
    return nil

  p.request.id = assignIpcRequestId(requestDomain, addr p.ipc)
  p.request.op = op
  p.request.blockIndex = blockIndex

  if op == SysBlockOpWrite:
    discard copyMem(addr p.request.data[0], data, SysBlockDataSize)

  wakeIpcWaiter(servicePid(serviceBlock))
  p


proc waitBlockResponse(p: ptr PendingBlockRequest): ptr SysBlockResponse =
  if not waitIpcReply(addr p.ipc, serviceBlock, waitBlockReq):
    return nil

  addr p.response


proc finishPending(p: ptr PendingBlockRequest) =
  finishIpcPending(p)


proc serviceBlockRead*(blockIndex: U64, outBlock: pointer): int =
  if outBlock == nil:
    return -1

  let req = queueBlockRequest(SysBlockOpRead, blockIndex, nil)
  if req == nil:
    if not canFallbackToRawBlock():
      return -1

    return blockdev.blockRead(blockIndex, outBlock)

  let resp = waitBlockResponse(req)
  if resp == nil or resp.result != 0:
    finishPending(req)
    return -1

  discard copyMem(outBlock, addr resp.data[0], SysBlockDataSize)
  finishPending(req)
  0


proc serviceBlockWrite*(blockIndex: U64, inBlock: pointer): int =
  if inBlock == nil:
    return -1

  let req = queueBlockRequest(SysBlockOpWrite, blockIndex, inBlock)
  if req == nil:
    if not canFallbackToRawBlock():
      return -1

    return blockdev.blockWrite(blockIndex, inBlock)

  let resp = waitBlockResponse(req)
  let outValue =
    if resp == nil:
      -1
    else:
      int(resp.result)

  finishPending(req)
  outValue


proc syscallBlockServiceRegister*(): U64 =
  if currentProc == nil or not currentProc.user.active:
    return U64(-1'i64)
  if serviceRegistered(serviceManager) and not currentIsService(serviceBlock):
    return U64(-1'i64)

  registerService(serviceBlock, currentProc.pid)
  0


proc syscallBlockServiceReceive*(outReq: U64): U64 =
  if outReq == 0 or not currentIsBlockServer():
    return U64(-1'i64)

  while true:
    var i = 0
    while i < BlockPendingMax:
      if pending[i].ipc.used and not pending[i].ipc.completed:
        if copyToUser(outReq, addr pending[i].request, U64(sizeof(SysBlockRequest))) != 0:
          return U64(-1'i64)

        return pending[i].request.id
      inc i

    sleepCurrentForIpc()


proc syscallBlockServiceReply*(respVal: U64): U64 =
  if respVal == 0 or not currentIsBlockServer():
    return U64(-1'i64)

  var resp: SysBlockResponse
  if copyFromUser(addr resp, respVal, U64(sizeof(SysBlockResponse))) != 0:
    return U64(-1'i64)

  let p = findPending(resp.id)
  if p == nil:
    return U64(-1'i64)

  p.response = resp
  p.ipc.completed = true
  wakeBlockWaiter(resp.id)
  0


proc syscallRawBlockRead*(blockIndex, outVal: U64): U64 =
  if not currentIsBlockServer() or outVal == 0:
    return U64(-1'i64)

  if blockdev.blockRead(blockIndex, addr rawBlockBuf[0]) != 0:
    return U64(-1'i64)
  if copyToUser(outVal, addr rawBlockBuf[0], SysBlockDataSize) != 0:
    return U64(-1'i64)

  0


proc syscallRawBlockWrite*(blockIndex, inVal: U64): U64 =
  if not currentIsBlockServer() or inVal == 0:
    return U64(-1'i64)

  if copyFromUser(addr rawBlockBuf[0], inVal, SysBlockDataSize) != 0:
    return U64(-1'i64)

  U64(blockdev.blockWrite(blockIndex, addr rawBlockBuf[0]))
