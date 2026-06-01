## Shutdown kernel
import ../../lib/core/app
import ../../lib/core/io
import ../../lib/core/syscall
import ../../lib/core/args


var parsedArgs: UserArgs


## Prints usage information.
proc printUsage() =
  write("usage: shutdown\n")
  write("       shutdown --help\n")


proc user_start*(arg: cstring) {.exportc, cdecl, noreturn.} =
  parseArgsOrExit(arg, parsedArgs, printUsage)
  exitIfHelp(parsedArgs, printUsage)
  requireArgc(parsedArgs, U32(0), printUsage)
  
  let uid = sysGetUid()
  if uid != 0:
    write("permission denied\n")
    sysExit(1)
  
  if sysShutdown() != 0:
    write("failed to shutdown kernel\n")
    sysExit(1)

  sysExit(0)
