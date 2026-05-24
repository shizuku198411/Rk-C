## Initializes, loads, and persists passwd, shadow, and group databases.

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
  appendStr(cstring"rkc:1000:1000:/home/rkc")
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
  appendStr(cstring"rkc:1000:rkc")
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


## Rebuilds /etc/shadow from built-in default root and rkc hashes.
proc resetShadowFile(): bool =
  shadowCount = U32(0)
  if not addShadowDefault(DefaultRootShadowLine):
    return false
  if not addShadowDefault(DefaultRkcShadowLine):
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


