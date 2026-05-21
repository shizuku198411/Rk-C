## Removes one or more empty directories from command-line paths.
import ../../lib/core/io
import ../../lib/core/args
import ../../lib/core/pathutils
import ../../lib/core/strutils
import ../../lib/core/syscall

var parsedArgs: UserArgs


## Prints rmdir usage information.
proc printUsage() =
  write("usage: rmdir <path> [path...]\n")


## Parses arguments and removes each requested directory.
proc user_start*(arg: cstring) {.exportc, cdecl, noreturn.} =
  if not parseUserArgs(arg, parsedArgs):
    printUsage()
    sysExit(1)

  if parsedArgs.argc == 1 and cstringEq(argAt(parsedArgs, 0), "--help"):
    printUsage()
    sysExit(0)

  if parsedArgs.argc == 0:
    printUsage()
    sysExit(1)

  var i = U32(0)
  while i < parsedArgs.argc:
    let path = resolvePath(argAt(parsedArgs, i))
    if path == nil:
      write("rmdir: path too long\n")
      sysExit(1)

    let rc = sysRmdir(path)
    if rc != 0:
      write("rmdir: failed\n")
      sysExit(1)

    inc i

  sysExit(0)
