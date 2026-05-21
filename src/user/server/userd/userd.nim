## Implements the user database service for passwd, shadow, group, and auth.
import ../../lib/core/io
import ../../lib/core/group
import ../../lib/core/passwd
import ../../lib/core/password_hash
import ../../lib/core/shadow
import ../../lib/core/strutils
import ../../lib/core/syscall
import ../lib/service_ready
import ../../../lib/user_ids


const
  PasswdPath = cstring"/etc/passwd"
  ShadowPath = cstring"/etc/shadow"
  GroupPath = cstring"/etc/group"
  UserMax = 8
  GroupMax = 8
  DbBufSize = 512
  ShadowFileMode = U32(0o600)
  DefaultRootShadowLine = cstring"root:pbkdf2-sha256:128:00112233445566778899aabbccddeeff:91b8f0d85f22d2563566e26377fc97f805e2302333e5c844414685a7ff2f3e0c"
  DefaultUserShadowLine = cstring"user:pbkdf2-sha256:128:102132435465768798a9babbdcddfe0f:2709f7572a8bf67f32948a07b3698578f13cd63ecf3162d2038855de5733fad8"


var
  packet: SysIpcPacket
  reply: SysIpcPacket
  dbBuf: array[DbBufSize, char]
  lineBuf: array[GroupLineMax, char]
  users: array[UserMax, PasswdEntry]
  shadowUsers: array[UserMax, ShadowEntry]
  groups: array[GroupMax, GroupEntry]
  userCount: U32
  shadowCount: U32
  groupCount: U32


## Writes a signed integer to the console for userd diagnostics.
proc writeI32(value: I32) =
  if value < 0:
    write("-")
    writeUnsigned(U64(-value))
    return

  writeUnsigned(U64(value))


## Clears the shared database file buffer.
proc clearDbBuf() =
  var i = 0
  while i < DbBufSize:
    dbBuf[i] = '\0'
    inc i


## Resets the default user resolve reply packet.
proc clearReply() =
  reply = SysIpcPacket()
  reply.op = SysIpcOpUserResolveResponse


## Writes the built-in passwd defaults into the database buffer.
proc copyDefaultPasswdToDb(): U32 =
  clearDbBuf()

  var pos = U32(0)

  template appendChar(ch: char) =
    if pos + U32(1) < U32(DbBufSize):
      dbBuf[pos] = ch
      inc pos
      dbBuf[pos] = '\0'

  template appendStr(s: cstring) =
    var i = U32(0)
    while s[i] != '\0':
      appendChar(s[i])
      inc i

  appendStr(cstring"root:0:0:/")
  appendChar(char(10))
  appendStr(cstring"user:1000:1000:/home")
  appendChar(char(10))
  pos


## Writes the built-in group defaults into the database buffer.
proc copyDefaultGroupToDb(): U32 =
  clearDbBuf()

  var pos = U32(0)

  template appendChar(ch: char) =
    if pos + U32(1) < U32(DbBufSize):
      dbBuf[pos] = ch
      inc pos
      dbBuf[pos] = '\0'

  template appendStr(s: cstring) =
    var i = U32(0)
    while s[i] != '\0':
      appendChar(s[i])
      inc i

  appendStr(cstring"root:0:root")
  appendChar(char(10))
  appendStr(cstring"user:1000:user")
  appendChar(char(10))
  pos


## Ensures /etc/passwd exists, creating the default database if needed.
proc ensurePasswdFile(): bool =
  clearDbBuf()
  let n = sysReadFile(PasswdPath, addr dbBuf[0], U64(DbBufSize - 1))
  if n > 0:
    dbBuf[U32(n)] = '\0'
    return true

  let size = copyDefaultPasswdToDb()
  let rc = sysWriteFileMode(
    PasswdPath,
    addr dbBuf[0],
    U64(size),
    SysFsWriteCreate or SysFsWriteOverwrite,
  )
  if rc != 0:
    write("[userd] failed to initialize /etc/passwd rc=")
    writeI32(rc)
    write("\n")
    return false

  true


## Ensures /etc/group exists, creating the default database if needed.
proc ensureGroupFile(): bool =
  clearDbBuf()
  let n = sysReadFile(GroupPath, addr dbBuf[0], U64(DbBufSize - 1))
  if n > 0:
    dbBuf[U32(n)] = '\0'
    return true

  let size = copyDefaultGroupToDb()
  let rc = sysWriteFileMode(
    GroupPath,
    addr dbBuf[0],
    U64(size),
    SysFsWriteCreate or SysFsWriteOverwrite,
  )
  if rc != 0:
    write("[userd] failed to initialize /etc/group rc=")
    writeI32(rc)
    write("\n")
    return false

  true


## Replaces /etc/passwd with the built-in default database.
proc resetPasswdFile(): bool =
  let size = copyDefaultPasswdToDb()
  let rc = sysWriteFileMode(
    PasswdPath,
    addr dbBuf[0],
    U64(size),
    SysFsWriteCreate or SysFsWriteOverwrite,
  )
  if rc != 0:
    write("[userd] failed to reset /etc/passwd rc=")
    writeI32(rc)
    write("\n")
    return false

  true


## Replaces /etc/group with the built-in default database.
proc resetGroupFile(): bool =
  let size = copyDefaultGroupToDb()
  let rc = sysWriteFileMode(
    GroupPath,
    addr dbBuf[0],
    U64(size),
    SysFsWriteCreate or SysFsWriteOverwrite,
  )
  if rc != 0:
    write("[userd] failed to reset /etc/group rc=")
    writeI32(rc)
    write("\n")
    return false

  true


## Persists the in-memory passwd entries to /etc/passwd.
proc saveUsers(): bool =
  clearDbBuf()

  var pos = U32(0)
  var i = U32(0)
  while i < userCount and i < U32(UserMax):
    let written = writePasswdLine(addr dbBuf[pos], U32(DbBufSize) - pos, users[i])
    if written == U32(0) or pos + written >= U32(DbBufSize):
      return false

    pos += written
    inc i

  let rc = sysWriteFileMode(
    PasswdPath,
    addr dbBuf[0],
    U64(pos),
    SysFsWriteCreate or SysFsWriteOverwrite,
  )
  if rc != 0:
    write("[userd] failed to save /etc/passwd rc=")
    writeI32(rc)
    write("\n")
    return false

  true


## Persists the in-memory shadow entries to /etc/shadow with restricted mode.
proc saveShadowUsers(): bool =
  clearDbBuf()

  var pos = U32(0)
  var i = U32(0)
  while i < shadowCount and i < U32(UserMax):
    let written = writeShadowLine(addr dbBuf[pos], U32(DbBufSize) - pos, shadowUsers[i])
    if written == U32(0) or pos + written >= U32(DbBufSize):
      return false

    pos += written
    inc i

  let rc = sysWriteFileMode(
    ShadowPath,
    addr dbBuf[0],
    U64(pos),
    SysFsWriteCreate or SysFsWriteOverwrite,
  )
  if rc != 0:
    write("[userd] failed to save /etc/shadow rc=")
    writeI32(rc)
    write("\n")
    return false

  discard sysChmod(ShadowPath, ShadowFileMode)
  true


## Adds one built-in shadow line to the in-memory shadow table.
proc addShadowDefault(line: cstring): bool =
  if shadowCount >= U32(UserMax):
    return false

  var entry: ShadowEntry
  if not parseShadowLine(line, entry):
    return false

  shadowUsers[shadowCount] = entry
  inc shadowCount
  true


## Rebuilds /etc/shadow from built-in default root and user hashes.
proc resetShadowFile(): bool =
  shadowCount = U32(0)
  if not addShadowDefault(DefaultRootShadowLine):
    return false
  if not addShadowDefault(DefaultUserShadowLine):
    return false

  saveShadowUsers()


## Ensures /etc/shadow exists and has restricted permissions.
proc ensureShadowFile(): bool =
  clearDbBuf()
  let n = sysReadFile(ShadowPath, addr dbBuf[0], U64(DbBufSize - 1))
  if n > 0:
    dbBuf[U32(n)] = '\0'
    discard sysChmod(ShadowPath, ShadowFileMode)
    return true

  resetShadowFile()


## Loads passwd entries from /etc/passwd into memory.
proc loadUsers(): bool =
  clearDbBuf()
  let n = sysReadFile(PasswdPath, addr dbBuf[0], U64(DbBufSize - 1))
  if n < 0:
    write("[userd] failed to read /etc/passwd rc=")
    writeI32(n)
    write("\n")
    return false

  dbBuf[U32(n)] = '\0'
  userCount = U32(0)

  var pos = 0
  while userCount < U32(UserMax):
    let len = getLine(addr dbBuf[0], int(n), pos, addr lineBuf[0], int(PasswdLineMax))
    if len <= 0:
      break

    var entry: PasswdEntry
    if parsePasswdLine(cast[cstring](addr lineBuf[0]), entry):
      users[userCount] = entry
      inc userCount

  if userCount == U32(0):
    write("[userd] no valid users in /etc/passwd\n")
    return false

  true


## Loads shadow entries from /etc/shadow into memory.
proc loadShadowUsers(): bool =
  clearDbBuf()
  let n = sysReadFile(ShadowPath, addr dbBuf[0], U64(DbBufSize - 1))
  if n < 0:
    write("[userd] failed to read /etc/shadow rc=")
    writeI32(n)
    write("\n")
    return false

  dbBuf[U32(n)] = '\0'
  shadowCount = U32(0)

  var pos = 0
  while shadowCount < U32(UserMax):
    let len = getLine(addr dbBuf[0], int(n), pos, addr lineBuf[0], int(ShadowLineMax))
    if len <= 0:
      break

    var entry: ShadowEntry
    if parseShadowLine(cast[cstring](addr lineBuf[0]), entry):
      shadowUsers[shadowCount] = entry
      inc shadowCount

  if shadowCount == U32(0):
    write("[userd] no valid users in /etc/shadow\n")
    return false

  true


## Loads group entries from /etc/group into memory.
proc loadGroups(): bool =
  clearDbBuf()
  let n = sysReadFile(GroupPath, addr dbBuf[0], U64(DbBufSize - 1))
  if n < 0:
    write("[userd] failed to read /etc/group rc=")
    writeI32(n)
    write("\n")
    return false

  dbBuf[U32(n)] = '\0'
  groupCount = U32(0)

  var pos = 0
  while groupCount < U32(GroupMax):
    let len = getLine(addr dbBuf[0], int(n), pos, addr lineBuf[0], int(GroupLineMax))
    if len <= 0:
      break

    var entry: GroupEntry
    if parseGroupLine(cast[cstring](addr lineBuf[0]), entry):
      groups[groupCount] = entry
      inc groupCount

  if groupCount == U32(0):
    write("[userd] no valid groups in /etc/group\n")
    return false

  true


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


## Adds a built-in default shadow entry when it is missing.
proc ensureDefaultShadow(name, line: cstring): bool =
  if findShadowByName(name) != nil:
    return false
  if addShadowDefault(line):
    return true

  false


## Replaces an existing shadow entry with a built-in default line.
proc replaceShadowDefault(name, line: cstring): bool =
  let shadow = findShadowByName(name)
  if shadow == nil:
    return false

  var entry: ShadowEntry
  if not parseShadowLine(line, entry):
    return false

  shadow[] = entry
  true


## Migrates default accounts when older or invalid shadow entries are found.
proc migrateMissingShadowUsers(): bool =
  var changed = false

  if ensureDefaultShadow(cstring"root", DefaultRootShadowLine):
    changed = true

  if ensureDefaultShadow(cstring"user", DefaultUserShadowLine):
    changed = true

  let rootShadow = findShadowByName(cstring"root")
  if rootShadow != nil and not verifyPassword(rootShadow[], cstring"root"):
    if not replaceShadowDefault(cstring"root", DefaultRootShadowLine):
      return false

    changed = true

  let userShadow = findShadowByName(cstring"user")
  if userShadow != nil and not verifyPassword(userShadow[], cstring"user"):
    if not replaceShadowDefault(cstring"user", DefaultUserShadowLine):
      return false

    changed = true

  if changed:
    return saveShadowUsers()

  true


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


## Initializes user databases, marks userd ready, and serves IPC requests.
proc user_start*(arg: cstring) {.exportc, cdecl, noreturn.} =
  discard arg

  if not waitUntilServiceRegistered(SysServiceKindUser):
    write("[userd] service registration timeout\n")
    sysExit(1)

  if not ensurePasswdFile() or (not loadUsers() and (not resetPasswdFile() or not loadUsers())):
    write("[userd] failed to load /etc/passwd\n")
    sysExit(1)

  discard saveUsers()

  if not ensureShadowFile() or (not loadShadowUsers() and (not resetShadowFile() or not loadShadowUsers())):
    write("[userd] failed to load /etc/shadow\n")
    sysExit(1)

  if not migrateMissingShadowUsers():
    write("[userd] failed to migrate /etc/shadow\n")
    sysExit(1)

  if not ensureGroupFile() or (not loadGroups() and (not resetGroupFile() or not loadGroups())):
    write("[userd] failed to load /etc/group\n")
    sysExit(1)

  notifyServiceReady(SysServiceKindUser)

  while true:
    if sysIpcReceivePacket(addr packet) < 0:
      write("[userd] receive failed\n")
      sysExit(1)

    handlePacket()
