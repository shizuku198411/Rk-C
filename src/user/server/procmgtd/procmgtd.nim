import ../../lib/core/syscall
import ../../lib/ipc/packet_data
import ../../../lib/syscall_caps
import ../lib/service_ready

const
  ProcessCap = int(SysProcessMaxSlots)
  SendRetries = 64

var
  requestPacket: SysIpcPacket
  replyPacket: SysIpcPacket
  processes: array[ProcessCap, SysProcessInfo]


proc copyProcessToPacket(packet: ptr SysIpcPacket, entry: ptr SysProcessInfo) =
  discard copyToPacketData(packet, entry, U32(sizeof(SysProcessInfo)))


proc sendPacketWithRetry(targetPid: I32, packet: ptr SysIpcPacket): bool =
  var tries = 0
  while tries < SendRetries:
    if sysIpcSendPacket(targetPid, packet) == 0:
      discard sysYield()
      return true

    discard sysYield()
    inc tries

  false


proc sendListResponse(targetPid: I32, count: I32): bool =
  replyPacket = SysIpcPacket()
  replyPacket.op = SysIpcOpProcListResponse
  replyPacket.arg0 = U64(count)
  sendPacketWithRetry(targetPid, addr replyPacket)


proc sendProcessEntry(targetPid: I32, index: I32, count: I32): bool =
  replyPacket = SysIpcPacket()
  replyPacket.op = SysIpcOpProcListEntry
  replyPacket.arg0 = U64(index)
  replyPacket.arg1 = U64(count)
  copyProcessToPacket(addr replyPacket, addr processes[index])
  sendPacketWithRetry(targetPid, addr replyPacket)


proc handleListRequest(senderPid: I32, maxEntries: I32, flags: U64) =
  var limit = maxEntries
  if limit <= 0 or limit > I32(ProcessCap):
    limit = I32(ProcessCap)

  let count = sysPs(addr processes[0], U64(limit), flags)
  if count < 0:
    discard sendListResponse(senderPid, -1)
    return

  if not sendListResponse(senderPid, count):
    return

  var i = I32(0)
  while i < count:
    if not sendProcessEntry(senderPid, i, count):
      return
    inc i


proc sendKillResponse(targetPid: I32, result: I32) =
  replyPacket = SysIpcPacket()
  replyPacket.op = SysIpcOpProcKillResponse
  replyPacket.arg0 = U64(result)
  discard sendPacketWithRetry(targetPid, addr replyPacket)


proc handleKillRequest(senderPid: I32, targetPid: I32) =
  let result = sysKill(targetPid)
  sendKillResponse(senderPid, result)


proc handleKillDeny(senderPid: I32) =
  sendKillResponse(senderPid, I32(-1'i32))


proc handlePacket(packet: ptr SysIpcPacket) =
  if packet.op == SysIpcOpProcListRequest:
    handleListRequest(packet.senderPid, I32(packet.arg0), packet.arg1)
    return

  if packet.op == SysIpcOpProcKillRequest:
    if (packet.capabilityMask and SysCapProcessKill) == 0:
      handleKillDeny(packet.senderPid)
      return
    handleKillRequest(packet.senderPid, I32(packet.arg0))
    return


proc user_start*(arg: cstring) {.exportc, cdecl, noreturn.} =
  discard arg

  notifyServiceReady(SysServiceKindProcess)

  while true:
    if sysIpcReceivePacket(addr requestPacket) == 0:
      handlePacket(addr requestPacket)
