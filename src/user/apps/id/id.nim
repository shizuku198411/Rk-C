## Prints the current uid/gid and resolves their names when available.
import ../../lib/core/args
import ../../lib/core/app
import ../../lib/core/group
import ../../lib/core/io
import ../../lib/core/passwd
import ../../lib/core/syscall
import ../../lib/core/userdb


var parsedArgs: UserArgs


## Prints id usage information.
proc printUsage() =
  write("usage: id\n")
  write("       id --help\n")


## Reads current identity and prints uid/gid with optional names.
proc user_start*(arg: cstring) {.exportc, cdecl, noreturn.} =
  parseArgsOrExit(arg, parsedArgs, printUsage)
  exitIfHelp(parsedArgs, printUsage)
  requireArgc(parsedArgs, U32(0), printUsage)

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
