import ../../../lib/mem
import ../../../lib/syscall_types
import ../../../lib/types
import ../../fs/blockdev
import ../../mm/usercopy
import ../../task/process

const
  BlockPendingMax = 8
  BlockSize* = blockdev.BlockSize

type
  PendingBlockRequest = object
    used: bool
    completed: bool
    request: SysBlockRequest
    response: SysBlockResponse

var
  blockServerPid: int32
  blockServerRegistered: bool
  nextReqId = U64(1)
  pending: array[BlockPendingMax, PendingBlockRequest]
  rawBlockBuf: array[SysBlockDataSize, U8]


proc blockServiceInit*() =
  blockdevInit()


proc currentIsBlockServer(): bool =
  currentProc != nil and blockServerPid != 0 and currentProc.pid == blockServerPid


proc isBlockServicePid*(pid: int32): bool =
  blockServerRegistered and blockServerPid == pid


proc blockServerAvailable(): bool =
  let p = findProcessByPid(blockServerPid)
  p != nil and p.state != procZombie and p.state != procUnused


proc canFallbackToRawBlock(): bool =
  not blockServerRegistered or currentIsBlockServer()


proc allocPending(): ptr PendingBlockRequest =
  var i = 0
  while i < BlockPendingMax:
    if not pending[i].used:
      pending[i] = PendingBlockRequest()
      pending[i].used = true
      return addr pending[i]
    inc i

  nil


proc findPending(id: U64): ptr PendingBlockRequest =
  var i = 0
  while i < BlockPendingMax:
    if pending[i].used and pending[i].request.id == id:
      return addr pending[i]
    inc i

  nil


proc queueBlockRequest(op: U32, blockIndex: U64, data: pointer): ptr PendingBlockRequest =
  if not blockServerAvailable() or currentIsBlockServer():
    return nil

  let p = allocPending()
  if p == nil:
    return nil

  p.request.id = nextReqId
  inc nextReqId
  p.request.op = op
  p.request.blockIndex = blockIndex

  if op == SysBlockOpWrite:
    discard copyMem(addr p.request.data[0], data, SysBlockDataSize)

  wakeIpcWaiter(blockServerPid)
  p


proc waitBlockResponse(p: ptr PendingBlockRequest): ptr SysBlockResponse =
  while p.used and not p.completed:
    if not blockServerAvailable():
      return nil

    sleepCurrentForBlockReq(p.request.id)

  if not p.used:
    return nil

  addr p.response


proc finishPending(p: ptr PendingBlockRequest) =
  if p != nil:
    p[] = PendingBlockRequest()


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
  if currentProc == nil or not currentProc.isUser:
    return U64(-1'i64)

  blockServerPid = currentProc.pid
  blockServerRegistered = true
  0


proc syscallBlockServiceReceive*(outReq: U64): U64 =
  if outReq == 0 or not currentIsBlockServer():
    return U64(-1'i64)

  while true:
    var i = 0
    while i < BlockPendingMax:
      if pending[i].used and not pending[i].completed:
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
  p.completed = true
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
