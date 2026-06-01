## Writes command-line arguments to stdout.
import ../../lib/core/io
import ../../lib/core/args
import ../../lib/core/app
import ../../lib/core/syscall


var parsedArgs: UserArgs


## Prints echo usage information.
proc printUsage() =
  write("usage: echo \"<str1 [str2...]>\"\n")


## Prints parsed arguments separated by spaces.
proc user_start*(arg: cstring) {.exportc, cdecl, noreturn.} =
  parseArgsOrExit(arg, parsedArgs, printUsage)
  exitIfHelp(parsedArgs, printUsage)
  requireMinArgc(parsedArgs, U32(1), printUsage)
  
  var i = U32(0)
  while i < parsedArgs.argc:
    write(argAt(parsedArgs, i))
    if i != parsedArgs.argc - 1:
      write(" ")
    inc i
  write("\n")
  
  sysExit(0)
