import ../../lib/io
import ../../lib/strutils
import ../../lib/syscall

var
  services: array[8, SysServiceInfo]
  requestPacket: SysIpcPacket
  responsePacket: SysIpcPacket


proc parsePid(arg: cstring): I32 =
  if isEmpty(arg):
    return -1

  var i = 0
  var pid = I32(0)
  while arg[i] >= '0' and arg[i] <= '9':
    pid = pid * 10 + I32(ord(arg[i]) - ord('0'))
    inc i

  if arg[i] != '\0':
    return -1

  pid


proc processManagerPid(): I32 =
  let count = sysServiceList(addr services[0], U64(len(services)))
  if count < 0:
    return -1

  var i = I32(0)
  while i < count:
    if services[i].kind == SysServiceKindProcess and services[i].available != 0:
      return services[i].pid
    inc i

  -1


proc requestKill(targetPid: I32): I32 =
  let pid = processManagerPid()
  if pid <= 0:
    return -1

  requestPacket = SysIpcPacket()
  requestPacket.op = SysIpcOpProcKillRequest
  requestPacket.arg0 = U64(targetPid)
  if sysIpcSendPacket(pid, addr requestPacket) != 0:
    return -1

  if sysIpcReceivePacket(addr responsePacket) != 0:
    return -1
  if responsePacket.op != SysIpcOpProcKillResponse:
    return -1

  I32(responsePacket.arg0)


proc user_start*(arg: cstring) {.exportc, cdecl, noreturn.} =
  let pid = parsePid(arg)
  if pid <= 0:
    write("usage: kill <pid>\n")
    sysExit(1)

  if requestKill(pid) != 0:
    write("kill: failed\n")
    sysExit(1)

  sysExit(0)
