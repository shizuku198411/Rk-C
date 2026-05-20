import ../../lib/core/args
import ../../lib/core/io
import ../../lib/core/strutils
import ../../lib/core/syscall


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

  write("uid=")
  writeUnsigned(U64(sysGetUid()))
  write(" gid=")
  writeUnsigned(U64(sysGetGid()))
  write("\n")
  sysExit(0)
