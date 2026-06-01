## Creates files or updates their presence using write-file semantics.
import ../../lib/core/io
import ../../lib/core/args
import ../../lib/core/app
import ../../lib/core/syscall
import ../../lib/core/pathutils


var parsedArgs: UserArgs


## Prints touch usage information.
proc printUsage() =
  write("usage: touch <path>\n")


## Parses arguments and ensures each requested file exists.
proc user_start*(arg: cstring) {.exportc, cdecl, noreturn.} =
  parseArgsOrExit(arg, parsedArgs, printUsage)
  exitIfHelp(parsedArgs, printUsage)
  requireMinArgc(parsedArgs, U32(1), printUsage)
  
  var 
    buffer: array[1, char]
    i = U32(0)
  while i < parsedArgs.argc:
    let path = resolvePath(argAt(parsedArgs, i))
    if path == nil:
      write("path too long\n")
      sysExit(1)
    
    if sysWriteFileMode(path, addr buffer[0], 0, SysFsWriteCreate or SysFsWriteOverwrite) != 0:
      write("failed to create file\n")
      sysExit(1)
    inc i
  
  sysExit(0)
