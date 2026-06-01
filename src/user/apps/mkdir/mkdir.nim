## Creates one or more directories from command-line paths.
import ../../lib/core/io
import ../../lib/core/args
import ../../lib/core/app
import ../../lib/core/pathutils
import ../../lib/core/syscall

var parsedArgs: UserArgs


## Prints mkdir usage information.
proc printUsage() =
  write("usage: mkdir <path> [path...]\n")


## Parses arguments and creates each requested directory.
proc user_start*(arg: cstring) {.exportc, cdecl, noreturn.} =
  parseArgsOrExit(arg, parsedArgs, printUsage)
  exitIfHelp(parsedArgs, printUsage)
  requireMinArgc(parsedArgs, U32(1), printUsage)

  var i: U32 = 0
  while i < parsedArgs.argc:
    let path = resolvePath(argAt(parsedArgs, i))
    if path == nil:
      write("mkdir: path too long\n")
      sysExit(1)

    let rc = sysMkdir(path)
    if rc != 0:
      write("mkdir: failed\n")
      sysExit(1)
    inc i
  sysExit(0)
