## Shutdown kernel
import ../../lib/core/io
import ../../lib/core/strutils
import ../../lib/core/syscall
import ../../lib/core/args


var parsedArgs: UserArgs


## Prints usage information.
proc printUsage() =
  write("usage: shutdown\n")
  write("       shutdown --help\n")


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
  if uid != 0:
    write("permission denied\n")
    sysExit(1)
  
  if sysShutdown() != 0:
    write("failed to shutdown kernel\n")
    sysExit(1)

  sysExit(0)