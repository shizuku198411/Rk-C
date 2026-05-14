import ../../lib/core/io
import ../../lib/core/args
import ../../lib/core/strutils
import ../../lib/core/syscall

var parsedArgs: UserArgs


proc printUsage() =
  write("usage: rmdir <path>\n")


proc user_start*(arg: cstring) {.exportc, cdecl, noreturn.} =
  if not parseUserArgs(arg, parsedArgs):
    printUsage()
    sysExit(1)

  if parsedArgs.argc == 1 and streq(argAt(parsedArgs, 0), "--help"):
    printUsage()
    sysExit(0)

  if parsedArgs.argc != 1:
    printUsage()
    sysExit(1)

  let rc = sysRmdir(argAt(parsedArgs, 0))
  if rc != 0:
    write("rmdir: failed\n")
    sysExit(1)
  sysExit(0)
