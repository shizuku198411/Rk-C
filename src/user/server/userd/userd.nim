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
  DefaultRkcShadowLine = cstring"rkc:pbkdf2-sha256:128:102132435465768798a9babbdcddfe0f:e68bd965923c84d6305f4fbdd65017367e4f7ae6e589a60cfc5b3edc1391bcfa"


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


## Includes initializes, loads, and persists passwd, shadow, and group databases.
include ./internal/database


## Includes resolves users and handles authentication and password-update ipc.
include ./internal/protocol


## Initializes user databases, marks userd ready, and serves IPC requests.
proc user_start*(arg: cstring) {.exportc, cdecl, noreturn.} =
  discard arg

  if not waitUntilServiceRegistered(SysServiceKindUser):
    write("[userd] service registration timeout\n")
    sysExit(1)

  if not ensurePasswdFile() or (not loadUsers() and (not resetPasswdFile() or not loadUsers())):
    write("[userd] failed to load /etc/passwd\n")
    sysExit(1)

  if not ensureShadowFile() or (not loadShadowUsers() and (not resetShadowFile() or not loadShadowUsers())):
    write("[userd] failed to load /etc/shadow\n")
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
