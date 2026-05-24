## Resolves users and handles authentication and password-update IPC.

## Finds an in-memory passwd entry by username.
proc findUserByName(name: cstring): ptr PasswdEntry =
  var i = U32(0)
  while i < userCount:
    if cstringEq(cast[cstring](addr users[i].name[0]), name):
      return addr users[i]
    inc i

  nil


## Finds an in-memory passwd entry by uid.
proc findUserByUid(uid: U32): ptr PasswdEntry =
  var i = U32(0)
  while i < userCount:
    if users[i].uid == uid:
      return addr users[i]
    inc i

  nil


## Finds an in-memory shadow entry by username.
proc findShadowByName(name: cstring): ptr ShadowEntry =
  var i = U32(0)
  while i < shadowCount:
    if cstringEq(cast[cstring](addr shadowUsers[i].name[0]), name):
      return addr shadowUsers[i]
    inc i

  nil


## Finds an in-memory group entry by group name.
proc findGroupByName(name: cstring): ptr GroupEntry =
  var i = U32(0)
  while i < groupCount:
    if cstringEq(cast[cstring](addr groups[i].name[0]), name):
      return addr groups[i]
    inc i

  nil


## Finds an in-memory group entry by gid.
proc findGroupByGid(gid: U32): ptr GroupEntry =
  var i = U32(0)
  while i < groupCount:
    if groups[i].gid == gid:
      return addr groups[i]
    inc i

  nil


## Sends a passwd resolve response to the requesting process.
proc sendResolveReply(toPid: I32, entry: ptr PasswdEntry) =
  clearReply()
  if entry == nil:
    reply.arg0 = U64(-1'i64)
    discard sysIpcSendPacket(toPid, addr reply)
    return

  reply.arg0 = U64(0)
  reply.len = writePasswdPublicLine(addr reply.data[0], SysIpcMessageMax, entry[])
  discard sysIpcSendPacket(toPid, addr reply)


## Sends a group resolve response to the requesting process.
proc sendGroupResolveReply(toPid: I32, entry: ptr GroupEntry) =
  reply = SysIpcPacket()
  reply.op = SysIpcOpGroupResolveResponse
  if entry == nil:
    reply.arg0 = U64(-1'i64)
    discard sysIpcSendPacket(toPid, addr reply)
    return

  reply.arg0 = U64(0)
  reply.len = writeGroupLine(addr reply.data[0], SysIpcMessageMax, entry[])
  discard sysIpcSendPacket(toPid, addr reply)


## Returns a C string view into the current packet payload.
proc nextPacketCString(start: U32): cstring =
  if start >= SysIpcMessageMax:
    return nil

  cast[cstring](addr packet.data[start])


## Finds the end offset of a NUL-terminated packet string.
proc packetStringEnd(start: U32): U32 =
  var pos = start
  while pos < SysIpcMessageMax and packet.data[pos] != '\0':
    inc pos

  pos


## Sends an authentication response with a public passwd entry on success.
proc sendAuthReply(toPid: I32, entry: ptr PasswdEntry, ok: bool) =
  reply = SysIpcPacket()
  reply.op = SysIpcOpUserAuthResponse
  if not ok or entry == nil:
    reply.arg0 = U64(-1'i64)
    discard sysIpcSendPacket(toPid, addr reply)
    return

  reply.arg0 = U64(0)
  reply.len = writePasswdPublicLine(addr reply.data[0], SysIpcMessageMax, entry[])
  discard sysIpcSendPacket(toPid, addr reply)


## Handles a username/password authentication request.
proc handleAuthRequest() =
  let name = nextPacketCString(U32(0))
  let nameEnd = packetStringEnd(U32(0))
  if name == nil or nameEnd + U32(1) >= SysIpcMessageMax:
    sendAuthReply(packet.senderPid, nil, false)
    return

  let password = nextPacketCString(nameEnd + U32(1))
  let entry = findUserByName(name)
  let shadow = findShadowByName(name)
  if entry == nil or shadow == nil:
    sendAuthReply(packet.senderPid, nil, false)
    return

  let ok = verifyPassword(shadow[], password)
  sendAuthReply(
    packet.senderPid,
    entry,
    ok,
  )


## Sends a password update response to the requesting process.
proc sendSetPasswordReply(toPid: I32, ok: bool) =
  reply = SysIpcPacket()
  reply.op = SysIpcOpUserSetPasswordResponse
  if ok:
    reply.arg0 = U64(0)
  else:
    reply.arg0 = U64(-1'i64)

  discard sysIpcSendPacket(toPid, addr reply)


## Handles a password update request and persists the new shadow hash.
proc handleSetPasswordRequest() =
  let targetUid = U32(packet.arg0)
  if packet.uid != RootUid and packet.uid != targetUid:
    sendSetPasswordReply(packet.senderPid, false)
    return

  let entry = findUserByUid(targetUid)
  if entry == nil:
    sendSetPasswordReply(packet.senderPid, false)
    return

  var shadow = findShadowByName(cast[cstring](addr entry.name[0]))
  if shadow == nil:
    if shadowCount >= U32(UserMax):
      sendSetPasswordReply(packet.senderPid, false)
      return

    var newShadow: ShadowEntry
    if not makePasswordHash(cast[cstring](addr entry.name[0]), cast[cstring](addr packet.data[0]), newShadow):
      sendSetPasswordReply(packet.senderPid, false)
      return

    shadowUsers[shadowCount] = newShadow
    inc shadowCount
    sendSetPasswordReply(packet.senderPid, saveShadowUsers())
    return

  if not makePasswordHash(cast[cstring](addr entry.name[0]), cast[cstring](addr packet.data[0]), shadow[]):
    sendSetPasswordReply(packet.senderPid, false)
    return

  sendSetPasswordReply(packet.senderPid, saveShadowUsers())


## Dispatches one received userd IPC packet by operation code.
proc handlePacket() =
  if packet.op == SysIpcOpUserResolveNameRequest:
    sendResolveReply(packet.senderPid, findUserByName(cast[cstring](addr packet.data[0])))
  elif packet.op == SysIpcOpUserResolveUidRequest:
    sendResolveReply(packet.senderPid, findUserByUid(U32(packet.arg0)))
  elif packet.op == SysIpcOpUserAuthRequest:
    handleAuthRequest()
  elif packet.op == SysIpcOpUserSetPasswordRequest:
    handleSetPasswordRequest()
  elif packet.op == SysIpcOpGroupResolveNameRequest:
    sendGroupResolveReply(packet.senderPid, findGroupByName(cast[cstring](addr packet.data[0])))
  elif packet.op == SysIpcOpGroupResolveGidRequest:
    sendGroupResolveReply(packet.senderPid, findGroupByGid(U32(packet.arg0)))


