import ../../lib/core/io
import ../../lib/core/args
import ../../lib/core/strutils
import ../../lib/core/syscall


const BufferSize = 512

var
  parsedArgs: UserArgs
  buffer: array[BufferSize, char]


proc printUsage() =
  write("usage: paniclog\n")
  write("       paniclog --help\n")


proc user_start*(arg: cstring) {.exportc, cdecl, noreturn.} =
  if not parseUserArgs(arg, parsedArgs):
    printUsage()
    sysExit(1)
  
  if parsedArgs.argc == 1 and cstringEq(argAt(parsedArgs, 0), "--help"):
    printUsage()
    sysExit(0)
  
  if parsedArgs.argc != 0:
    printUsage()
    sysExit(1)
  
  let readLen = sysReadFile(cstring("/var/log/user_panic.log"), addr buffer[0], U64(BufferSize))
  if readLen <= 0:
    write("no panic log\n")
    sysExit(0)
  
  if readLen > 0:
    discard sysWrite(addr buffer[0], U64(readLen))

  sysExit(0)
