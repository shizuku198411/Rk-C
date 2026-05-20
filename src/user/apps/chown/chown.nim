import ../../lib/core/args
import ../../lib/core/io
import ../../lib/core/pathutils
import ../../lib/core/strutils
import ../../lib/core/syscall
import ../../../lib/user_ids


var parsedArgs: UserArgs


proc printUsage() =
  write("usage: chown <uid>:<gid> <path>\n")
  write("       chown <root|user> <path>\n")
  write("       chown --help\n")


proc parseDecimal(s: cstring, value: var U32): bool =
  if s == nil or s[0] == '\0':
    return false

  var outValue = U32(0)
  var pos = U32(0)
  while s[pos] != '\0':
    if s[pos] < '0' or s[pos] > '9':
      return false

    outValue = outValue * U32(10) + U32(ord(s[pos]) - ord('0'))
    inc pos

  value = outValue
  true


proc parseOwnerSpec(spec: cstring, uid, gid: var U32): bool =
  if cstringEq(spec, "root"):
    uid = RootUid
    gid = RootGid
    return true

  if cstringEq(spec, "user"):
    uid = UserUid
    gid = UserGid
    return true

  var sep = U32(0)
  while spec[sep] != '\0' and spec[sep] != ':':
    inc sep

  if spec[sep] != ':':
    return false

  var uidBuf: array[16, char]
  var gidBuf: array[16, char]
  var i = U32(0)
  while i < sep and i + U32(1) < U32(sizeof(uidBuf)):
    uidBuf[i] = spec[i]
    inc i
  uidBuf[i] = '\0'

  i = U32(0)
  var pos = sep + U32(1)
  while spec[pos] != '\0' and i + U32(1) < U32(sizeof(gidBuf)):
    gidBuf[i] = spec[pos]
    inc i
    inc pos
  gidBuf[i] = '\0'

  parseDecimal(cast[cstring](addr uidBuf[0]), uid) and
    parseDecimal(cast[cstring](addr gidBuf[0]), gid)


proc printError() =
  let err = sysLastError()
  if err == SysErrPerm:
    write("chown: permission denied\n")
  elif err == SysErrInval:
    write("chown: invalid argument\n")
  else:
    write("chown: failed\n")


proc user_start*(arg: cstring) {.exportc, cdecl, noreturn.} =
  if not parseUserArgs(arg, parsedArgs):
    printUsage()
    sysExit(1)

  if parsedArgs.argc == 1 and cstringEq(argAt(parsedArgs, 0), "--help"):
    printUsage()
    sysExit(0)

  if parsedArgs.argc != 2:
    printUsage()
    sysExit(1)

  var uid: U32
  var gid: U32
  if not parseOwnerSpec(argAt(parsedArgs, 0), uid, gid):
    write("chown: invalid owner\n")
    sysExit(1)

  let path = resolvePath(argAt(parsedArgs, 1))
  if path == nil:
    write("chown: path too long\n")
    sysExit(1)

  if sysChown(path, uid, gid) != 0:
    printError()
    sysExit(1)

  sysExit(0)
