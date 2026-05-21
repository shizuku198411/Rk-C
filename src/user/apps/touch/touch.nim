## Creates files or updates their presence using write-file semantics.
import ../../lib/core/io
import ../../lib/core/args
import ../../lib/core/syscall
import ../../lib/core/pathutils
import ../../lib/core/strutils


var parsedArgs: UserArgs


## Prints touch usage information.
proc printUsage() =
  write("usage: touch <path>\n")


## Parses arguments and ensures each requested file exists.
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
