import ../../lib/core/syscall
import ../../lib/ipc/packet_data
import ../lib/service_ready

const
  ProcessCap = 16

var
  requestPacket: SysIpcPacket
  replyPacket: SysIpcPacket
  processes: array[ProcessCap, SysProcessInfo]


proc copyProcessToPacket(packet: ptr SysIpcPacket, entry: ptr SysProcessInfo) =
  discard copyToPacketData(packet, entry, U32(sizeof(SysProcessInfo)))


proc sendListResponse(targetPid: I32, count: I32) =
  replyPacket = SysIpcPacket()
  replyPacket.op = SysIpcOpProcListResponse
  replyPacket.arg0 = U64(count)
  discard sysIpcSendPacket(targetPid, addr replyPacket)


proc sendProcessEntry(targetPid: I32, index: I32, count: I32) =
  replyPacket = SysIpcPacket()
  replyPacket.op = SysIpcOpProcListEntry
  replyPacket.arg0 = U64(index)
  replyPacket.arg1 = U64(count)
  copyProcessToPacket(addr replyPacket, addr processes[index])
  discard sysIpcSendPacket(targetPid, addr replyPacket)


proc handleListRequest(senderPid: I32, maxEntries: I32) =
  var limit = maxEntries
  if limit <= 0 or limit > ProcessCap:
    limit = ProcessCap

  let count = sysPs(addr processes[0], U64(limit))
  if count < 0:
    sendListResponse(senderPid, -1)
    return

  sendListResponse(senderPid, count)

  var i = I32(0)
  while i < count:
    sendProcessEntry(senderPid, i, count)
    inc i


proc sendKillResponse(targetPid: I32, result: I32) =
  replyPacket = SysIpcPacket()
  replyPacket.op = SysIpcOpProcKillResponse
  replyPacket.arg0 = U64(result)
  discard sysIpcSendPacket(targetPid, addr replyPacket)


proc handleKillRequest(senderPid: I32, targetPid: I32) =
  let result = sysKill(targetPid)
  sendKillResponse(senderPid, result)


proc handlePacket(packet: ptr SysIpcPacket) =
  if packet.op == SysIpcOpProcListRequest:
    handleListRequest(packet.senderPid, I32(packet.arg0))
    return

  if packet.op == SysIpcOpProcKillRequest:
    handleKillRequest(packet.senderPid, I32(packet.arg0))
    return


proc user_start*(arg: cstring) {.exportc, cdecl, noreturn.} =
  discard arg

  notifyServiceReady(SysServiceKindProcess)

  while true:
    if sysIpcReceivePacket(addr requestPacket) == 0:
      handlePacket(addr requestPacket)
