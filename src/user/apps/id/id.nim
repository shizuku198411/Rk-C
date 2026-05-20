import ../../lib/core/args
import ../../lib/core/group
import ../../lib/core/io
import ../../lib/core/passwd
import ../../lib/core/strutils
import ../../lib/core/syscall
import ../../lib/core/userdb


var parsedArgs: UserArgs


proc printUsage() =
  write("usage: id\n")
  write("       id --help\n")


proc user_start*(arg: cstring) {.exportc, cdecl, noreturn.} =
  if not parseUserArgs(arg, parsedArgs):
    printUsage()
    sysExit(1)

  if parsedArgs.argc == 1 and cstringEq(argAt(parsedArgs, 0), "--help"):
    printUsage()
    sysExit(0)

  if parsedArgs.argc != 0:
    printUsage()
    sysExit(1)

  let uid = sysGetUid()
  let gid = sysGetGid()
  var entry: PasswdEntry
  var group: GroupEntry

  write("uid=")
  writeUnsigned(U64(uid))
  if resolveUid(uid, entry):
    write("(")
    write(cast[cstring](addr entry.name[0]))
    write(")")

  write(" gid=")
  writeUnsigned(U64(gid))
  if resolveGid(gid, group):
    write("(")
    write(cast[cstring](addr group.name[0]))
    write(")")

  write("\n")
  sysExit(0)
