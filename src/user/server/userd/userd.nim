import ../../lib/core/io
import ../../lib/core/group
import ../../lib/core/passwd
import ../../lib/core/strutils
import ../../lib/core/syscall
import ../lib/service_ready


const
  PasswdPath = cstring"/etc/passwd"
  GroupPath = cstring"/etc/group"
  UserMax = 8
  GroupMax = 8
  DbBufSize = 512


var
  packet: SysIpcPacket
  reply: SysIpcPacket
  dbBuf: array[DbBufSize, char]
  lineBuf: array[GroupLineMax, char]
  users: array[UserMax, PasswdEntry]
  groups: array[GroupMax, GroupEntry]
  userCount: U32
  groupCount: U32


proc writeI32(value: I32) =
  if value < 0:
    write("-")
    writeUnsigned(U64(-value))
    return

  writeUnsigned(U64(value))


proc clearDbBuf() =
  var i = 0
  while i < DbBufSize:
    dbBuf[i] = '\0'
    inc i


proc clearReply() =
  reply = SysIpcPacket()
  reply.op = SysIpcOpUserResolveResponse


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


proc findUserByName(name: cstring): ptr PasswdEntry =
  var i = U32(0)
  while i < userCount:
    if cstringEq(cast[cstring](addr users[i].name[0]), name):
      return addr users[i]
    inc i

  nil


proc findUserByUid(uid: U32): ptr PasswdEntry =
  var i = U32(0)
  while i < userCount:
    if users[i].uid == uid:
      return addr users[i]
    inc i

  nil


proc findGroupByName(name: cstring): ptr GroupEntry =
  var i = U32(0)
  while i < groupCount:
    if cstringEq(cast[cstring](addr groups[i].name[0]), name):
      return addr groups[i]
    inc i

  nil


proc findGroupByGid(gid: U32): ptr GroupEntry =
  var i = U32(0)
  while i < groupCount:
    if groups[i].gid == gid:
      return addr groups[i]
    inc i

  nil


proc sendResolveReply(toPid: I32, entry: ptr PasswdEntry) =
  clearReply()
  if entry == nil:
    reply.arg0 = U64(-1'i64)
    discard sysIpcSendPacket(toPid, addr reply)
    return

  reply.arg0 = U64(0)
  reply.len = writePasswdLine(addr reply.data[0], SysIpcMessageMax, entry[])
  discard sysIpcSendPacket(toPid, addr reply)


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


proc handlePacket() =
  if packet.op == SysIpcOpUserResolveNameRequest:
    sendResolveReply(packet.senderPid, findUserByName(cast[cstring](addr packet.data[0])))
  elif packet.op == SysIpcOpUserResolveUidRequest:
    sendResolveReply(packet.senderPid, findUserByUid(U32(packet.arg0)))
  elif packet.op == SysIpcOpGroupResolveNameRequest:
    sendGroupResolveReply(packet.senderPid, findGroupByName(cast[cstring](addr packet.data[0])))
  elif packet.op == SysIpcOpGroupResolveGidRequest:
    sendGroupResolveReply(packet.senderPid, findGroupByGid(U32(packet.arg0)))


proc user_start*(arg: cstring) {.exportc, cdecl, noreturn.} =
  discard arg

  if not waitUntilServiceRegistered(SysServiceKindUser):
    write("[userd] service registration timeout\n")
    sysExit(1)

  if not ensurePasswdFile() or (not loadUsers() and (not resetPasswdFile() or not loadUsers())):
    write("[userd] failed to load /etc/passwd\n")
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
