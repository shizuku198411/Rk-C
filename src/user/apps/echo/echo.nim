## Writes command-line arguments to stdout.
import ../../lib/core/io
import ../../lib/core/args
import ../../lib/core/syscall
import ../../lib/core/strutils


var parsedArgs: UserArgs


## Prints echo usage information.
proc printUsage() =
  write("usage: echo \"<str1 [str2...]>\"\n")


## Prints parsed arguments separated by spaces.
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
    write(argAt(parsedArgs, i))
    if i != parsedArgs.argc - 1:
      write(" ")
    inc i
  write("\n")
  
  sysExit(0)
