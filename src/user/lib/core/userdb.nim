import ../../../lib/syscall_types
import ../ipc/ipc_request
import ../ipc/service_client
import ./group
import ./passwd
import ./strutils
import ./syscall


var
  userRequest: SysIpcPacket
  userReply: SysIpcPacket
  userLine: array[GroupLineMax, char]


proc clearPacket(packet: var SysIpcPacket) =
  packet = SysIpcPacket()


proc copyCStringToPacket(packet: var SysIpcPacket, value: cstring): bool =
  var i = U32(0)
  while value[i] != '\0':
    if i + U32(1) >= SysIpcMessageMax:
      return false

    packet.data[i] = value[i]
    inc i

  packet.data[i] = '\0'
  packet.len = i
  true


proc copyAuthToPacket(packet: var SysIpcPacket, name, password: cstring): bool =
  var pos = U32(0)

  var i = U32(0)
  while name[i] != '\0':
    if pos + U32(1) >= SysIpcMessageMax:
      return false

    packet.data[pos] = name[i]
    inc pos
    inc i

  if pos + U32(1) >= SysIpcMessageMax:
    return false

  packet.data[pos] = '\0'
  inc pos

  i = U32(0)
  while password[i] != '\0':
    if pos + U32(1) >= SysIpcMessageMax:
      return false

    packet.data[pos] = password[i]
    inc pos
    inc i

  packet.data[pos] = '\0'
  packet.len = pos + U32(1)
  true


proc copyReplyLine(): cstring =
  var i = U32(0)
  while i + U32(1) < GroupLineMax and i < userReply.len:
    userLine[i] = userReply.data[i]
    inc i

  userLine[i] = '\0'
  cast[cstring](addr userLine[0])


proc requestUser(op: U32, name: cstring, uid: U32, entry: var PasswdEntry): bool =
  let pid = servicePidByKind(SysServiceKindUser)
  if pid <= 0:
    return false

  clearPacket(userRequest)
  userRequest.op = op
  userRequest.arg0 = U64(uid)
  if name != nil and not copyCStringToPacket(userRequest, name):
    return false

  if requestIpcReply(pid, addr userRequest, addr userReply, SysIpcOpUserResolveResponse) != 0:
    return false

  if userReply.arg0 != U64(0):
    return false

  parsePasswdLine(copyReplyLine(), entry)


proc resolveUser*(name: cstring, entry: var PasswdEntry): bool =
  if isEmpty(name):
    return false

  requestUser(SysIpcOpUserResolveNameRequest, name, U32(0), entry)


proc resolveUid*(uid: U32, entry: var PasswdEntry): bool =
  requestUser(SysIpcOpUserResolveUidRequest, nil, uid, entry)


proc authenticateUser*(name, password: cstring, entry: var PasswdEntry): bool =
  if isEmpty(name) or password == nil:
    return false

  let pid = servicePidByKind(SysServiceKindUser)
  if pid <= 0:
    return false

  clearPacket(userRequest)
  userRequest.op = SysIpcOpUserAuthRequest
  if not copyAuthToPacket(userRequest, name, password):
    return false

  if requestIpcReply(pid, addr userRequest, addr userReply, SysIpcOpUserAuthResponse) != 0:
    return false

  if userReply.arg0 != U64(0):
    return false

  parsePasswdLine(copyReplyLine(), entry)


proc setUserPassword*(uid: U32, password: cstring): bool =
  if password == nil:
    return false

  let pid = servicePidByKind(SysServiceKindUser)
  if pid <= 0:
    return false

  clearPacket(userRequest)
  userRequest.op = SysIpcOpUserSetPasswordRequest
  userRequest.arg0 = U64(uid)
  if not copyCStringToPacket(userRequest, password):
    return false

  if requestIpcReply(pid, addr userRequest, addr userReply, SysIpcOpUserSetPasswordResponse) != 0:
    return false

  userReply.arg0 == U64(0)


proc requestGroup(op: U32, name: cstring, gid: U32, entry: var GroupEntry): bool =
  let pid = servicePidByKind(SysServiceKindUser)
  if pid <= 0:
    return false

  clearPacket(userRequest)
  userRequest.op = op
  userRequest.arg0 = U64(gid)
  if name != nil and not copyCStringToPacket(userRequest, name):
    return false

  if requestIpcReply(pid, addr userRequest, addr userReply, SysIpcOpGroupResolveResponse) != 0:
    return false

  if userReply.arg0 != U64(0):
    return false

  parseGroupLine(copyReplyLine(), entry)


proc resolveGroup*(name: cstring, entry: var GroupEntry): bool =
  if isEmpty(name):
    return false

  requestGroup(SysIpcOpGroupResolveNameRequest, name, U32(0), entry)


proc resolveGid*(gid: U32, entry: var GroupEntry): bool =
  requestGroup(SysIpcOpGroupResolveGidRequest, nil, gid, entry)
