## Removes one or more files from command-line paths.
import ../../lib/core/io
import ../../lib/core/args
import ../../lib/core/app
import ../../lib/core/pathutils
import ../../lib/core/syscall

var parsedArgs: UserArgs


## Prints rm usage information.
proc printUsage() =
  write("usage: rm <path> [path...]\n")


## Parses arguments and removes each requested file.
proc user_start*(arg: cstring) {.exportc, cdecl, noreturn.} =
  parseArgsOrExit(arg, parsedArgs, printUsage)
  exitIfHelp(parsedArgs, printUsage)
  requireMinArgc(parsedArgs, U32(1), printUsage)

  var i = U32(0)
  while i < parsedArgs.argc:
    let path = resolvePath(argAt(parsedArgs, i))
    if path == nil:
      write("rm: path too long\n")
      sysExit(1)

    let rc = sysUnlink(path)
    if rc != 0:
      write("rm: failed\n")
      sysExit(1)

    inc i

  sysExit(0)
