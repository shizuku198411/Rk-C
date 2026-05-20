import ../../../lib/syscall_types
import ../../../lib/types
import ../../mm/usercopy
import ../../task/process
import ../syscall_cap

var sendBuf: array[SysIpcMessageMax, char]


proc enqueueIpc(target: ptr Process, packet: ptr SysIpcPacket): int =
  if target == nil or packet == nil:
    return -1
  if target.ipc.count >= SysIpcQueueCap:
    return -1

  target.ipc.queue[target.ipc.tail] = packet[]
  target.ipc.tail = (target.ipc.tail + 1) mod SysIpcQueueCap
  inc target.ipc.count
  0


proc dequeueIpc(p: ptr Process, packet: ptr SysIpcPacket): int =
  if p == nil or packet == nil:
    return -1
  if p.ipc.count <= 0:
    return -1

  packet[] = p.ipc.queue[p.ipc.head]
  p.ipc.queue[p.ipc.head] = SysIpcPacket()
  p.ipc.head = (p.ipc.head + 1) mod SysIpcQueueCap
  dec p.ipc.count
  0


proc packetToMessage(packet: ptr SysIpcPacket, msg: ptr SysIpcMessage) =
  msg[] = SysIpcMessage()
  msg.senderPid = packet.senderPid
  msg.len = packet.len

  var i = 0
  while i < SysIpcMessageMax:
    msg.data[i] = packet.data[i]
    if packet.data[i] == '\0':
      break
    inc i


proc sendPacket(target: ptr Process, packet: ptr SysIpcPacket): U64 =
  if target == nil or target.state == procZombie or target.state == procUnused:
    return U64(-1'i64)
  if packet.len > U32(SysIpcMessageMax):
    return U64(-1'i64)

  packet.senderPid = currentProc.pid
  packet.capabilityMask =
    if currentProc.user.active:
      currentProc.user.capabilityMask
    else:
      U32(0)
  packet.uid = currentProc.identity.uid
  packet.gid = currentProc.identity.gid
  if packet.len < U32(SysIpcMessageMax):
    packet.data[int(packet.len)] = '\0'

  if enqueueIpc(target, packet) != 0:
    return U64(-1'i64)

  wakeIpcWaiter(target.pid)
  0


proc syscallIpcSend*(pidVal, msgVal: U64): U64 =
  if currentProc == nil or msgVal == 0:
    return U64(-1'i64)

  let target = findProcessByPid(int32(pidVal))
  let copied = copyUserCString(addr sendBuf[0], msgVal, U64(SysIpcMessageMax))
  if copied < 0:
    return U64(-1'i64)

  var packet = SysIpcPacket()
  packet.op = SysIpcOpText
  packet.len = U32(copied)

  var i = 0
  while i < SysIpcMessageMax:
    packet.data[i] = sendBuf[i]
    if sendBuf[i] == '\0':
      break
    inc i

  sendPacket(target, addr packet)


proc syscallIpcReceive*(outMsg: U64): U64 =
  if currentProc == nil or outMsg == 0:
    return U64(-1'i64)

  var packet = SysIpcPacket()
  while dequeueIpc(currentProc, addr packet) != 0:
    sleepCurrentForIpc()

  var msg = SysIpcMessage()
  packetToMessage(addr packet, addr msg)
  if copyToUser(outMsg, addr msg, U64(sizeof(SysIpcMessage))) != 0:
    return U64(-1'i64)

  0


proc syscallIpcTryReceive*(outMsg: U64): U64 =
  if currentProc == nil or outMsg == 0:
    return U64(-1'i64)

  var packet = SysIpcPacket()
  if dequeueIpc(currentProc, addr packet) != 0:
    return U64(1)

  var msg = SysIpcMessage()
  packetToMessage(addr packet, addr msg)
  if copyToUser(outMsg, addr msg, U64(sizeof(SysIpcMessage))) != 0:
    return U64(-1'i64)

  0


proc syscallIpcSendPacket*(pidVal, packetVal: U64): U64 =
  if currentProc == nil or packetVal == 0:
    return U64(-1'i64)

  let target = findProcessByPid(int32(pidVal))
  var packet = SysIpcPacket()
  if copyFromUser(addr packet, packetVal, U64(sizeof(SysIpcPacket))) != 0:
    return U64(-1'i64)

  sendPacket(target, addr packet)


proc syscallIpcReceivePacket*(outPacket: U64): U64 =
  if currentProc == nil or outPacket == 0:
    return U64(-1'i64)

  var packet = SysIpcPacket()
  while dequeueIpc(currentProc, addr packet) != 0:
    sleepCurrentForIpc()

  if copyToUser(outPacket, addr packet, U64(sizeof(SysIpcPacket))) != 0:
    return U64(-1'i64)

  0


proc syscallIpcTryReceivePacket*(outPacket: U64): U64 =
  if currentProc == nil or outPacket == 0:
    return U64(-1'i64)

  var packet = SysIpcPacket()
  if dequeueIpc(currentProc, addr packet) != 0:
    return U64(1)

  if copyToUser(outPacket, addr packet, U64(sizeof(SysIpcPacket))) != 0:
    return U64(-1'i64)

  0


proc syscallKill*(pidVal: U64): U64 =
  let pid = int32(pidVal)
  if not canSyscallKillTarget(pid):
    return U64(-1'i64)

  let target = findProcessByPid(pid)
  if target == nil or target.state == procUnused or target.state == procZombie:
    return U64(-1'i64)

  if sendProcessSignal(pid, SysSignalTerminate) != 0:
    return U64(-1'i64)

  0
