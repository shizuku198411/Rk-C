import ../../lib/core/io
import ../../lib/ipc/ipc_request
import ../../lib/ipc/service_client
import ../../lib/core/strutils
import ../../lib/core/syscall

var
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
  servicePidByKind(SysServiceKindProcess)


proc requestKill(targetPid: I32): I32 =
  let pid = processManagerPid()
  if pid <= 0:
    return -1

  requestPacket = SysIpcPacket()
  requestPacket.op = SysIpcOpProcKillRequest
  requestPacket.arg0 = U64(targetPid)
  if requestIpcReply(pid, addr requestPacket, addr responsePacket, SysIpcOpProcKillResponse) != 0:
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
