import ../../../lib/syscall_types
import ../../../lib/types
import ../../mm/usercopy
import ../../service/registry
import ../../task/process

var sendBuf: array[SysIpcMessageMax, char]


proc enqueueIpc(target: ptr Process, msg: ptr SysIpcMessage): int =
  if target == nil or msg == nil:
    return -1
  if target.ipc.count >= SysIpcQueueCap:
    return -1

  target.ipc.queue[target.ipc.tail] = msg[]
  target.ipc.tail = (target.ipc.tail + 1) mod SysIpcQueueCap
  inc target.ipc.count
  0


proc dequeueIpc(p: ptr Process, msg: ptr SysIpcMessage): int =
  if p == nil or msg == nil:
    return -1
  if p.ipc.count <= 0:
    return -1

  msg[] = p.ipc.queue[p.ipc.head]
  p.ipc.queue[p.ipc.head] = SysIpcMessage()
  p.ipc.head = (p.ipc.head + 1) mod SysIpcQueueCap
  dec p.ipc.count
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
  if isServicePid(pid):
    return U64(-1'i64)

  let target = findProcessByPid(pid)
  if target == nil or target.state == procUnused or target.state == procZombie:
    return U64(-1'i64)

  target.exitStatus = U64(255)
  clearWait(target)
  target.state = procZombie
  wakePidWaiters(pid)

  if currentProc == target:
    schedule()

  0
