import ../../lib/core/io
import ../../lib/core/args
import ../../lib/core/pathutils
import ../../lib/core/strutils
import ../../lib/core/syscall

var parsedArgs: UserArgs


proc printUsage() =
  write("usage: mkdir <path> [path...]\n")


proc user_start*(arg: cstring) {.exportc, cdecl, noreturn.} =
  if not parseUserArgs(arg, parsedArgs):
    printUsage()
    sysExit(1)

  if parsedArgs.argc == 1 and streq(argAt(parsedArgs, 0), "--help"):
    printUsage()
    sysExit(0)

  if parsedArgs.argc == 0:
    printUsage()
    sysExit(1)

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
