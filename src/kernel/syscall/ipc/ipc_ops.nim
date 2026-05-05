import ../../../lib/syscall_types
import ../../../lib/types
import ../../mm/usercopy
import ../../syscall/blk/block_service_ops
import ../../syscall/fs/fs_service_ops
import ../../task/process

var sendBuf: array[SysIpcMessageMax, char]


proc enqueueIpc(target: ptr Process, msg: ptr SysIpcMessage): int =
  if target == nil or msg == nil:
    return -1
  if target.ipcCount >= SysIpcQueueCap:
    return -1

  target.ipcQueue[target.ipcTail] = msg[]
  target.ipcTail = (target.ipcTail + 1) mod SysIpcQueueCap
  inc target.ipcCount
  0


proc dequeueIpc(p: ptr Process, msg: ptr SysIpcMessage): int =
  if p == nil or msg == nil:
    return -1
  if p.ipcCount <= 0:
    return -1

  msg[] = p.ipcQueue[p.ipcHead]
  p.ipcQueue[p.ipcHead] = SysIpcMessage()
  p.ipcHead = (p.ipcHead + 1) mod SysIpcQueueCap
  dec p.ipcCount
  0


proc syscallIpcSend*(pidVal, msgVal: U64): U64 =
  if currentProc == nil or msgVal == 0:
    return U64(-1'i64)

  let target = findProcessByPid(int32(pidVal))
  if target == nil or target.state == procZombie or target.state == procUnused:
    return U64(-1'i64)

  let copied = copyUserCString(addr sendBuf[0], msgVal, U64(SysIpcMessageMax))
  if copied < 0:
    return U64(-1'i64)

  var msg = SysIpcMessage()
  msg.senderPid = currentProc.pid
  msg.len = U32(copied)

  var i = 0
  while i < SysIpcMessageMax:
    msg.data[i] = sendBuf[i]
    if sendBuf[i] == '\0':
      break
    inc i

  if enqueueIpc(target, addr msg) != 0:
    return U64(-1'i64)

  wakeIpcWaiter(target.pid)
  0


proc syscallIpcReceive*(outMsg: U64): U64 =
  if currentProc == nil or outMsg == 0:
    return U64(-1'i64)

  var msg = SysIpcMessage()
  while dequeueIpc(currentProc, addr msg) != 0:
    sleepCurrentForIpc()

  if copyToUser(outMsg, addr msg, U64(sizeof(SysIpcMessage))) != 0:
    return U64(-1'i64)

  0


proc syscallKill*(pidVal: U64): U64 =
  let pid = int32(pidVal)
  if pid <= 1:
    return U64(-1'i64)
  if isBlockServicePid(pid) or isFsServicePid(pid):
    return U64(-1'i64)

  let target = findProcessByPid(pid)
  if target == nil or target.state == procUnused or target.state == procZombie:
    return U64(-1'i64)

  target.exitStatus = U64(255)
  target.waitingForInput = false
  target.waitingForIpc = false
  target.waitingForFsReq = 0
  target.waitingForBlockReq = 0
  target.waitingForPid = 0
  target.state = procZombie
  wakePidWaiters(pid)

  if currentProc == target:
    schedule()

  0
