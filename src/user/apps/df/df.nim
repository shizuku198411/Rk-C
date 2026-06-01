## Prints filesystem capacity and usage information from procfs.
import ../../lib/core/args
import ../../lib/core/app
import ../../lib/core/io
import ../../lib/core/syscall


const DfBufferSize = 512

var
  parsedArgs: UserArgs
  buffer: array[DfBufferSize, char]


## Prints df usage information.
proc printUsage() =
  write("usage: df\n")
  write("       df --help\n")


## Reads /proc/fsinfo and writes the result to stdout.
proc user_start*(arg: cstring) {.exportc, cdecl, noreturn.} =
  parseArgsOrExit(arg, parsedArgs, printUsage)
  exitIfHelp(parsedArgs, printUsage)
  requireArgc(parsedArgs, U32(0), printUsage)

  let readLen = sysReadFile(cstring"/proc/fsinfo", addr buffer[0], U64(DfBufferSize))
  if readLen < 0:
    write("df: failed to read /proc/fsinfo\n")
    sysExit(1)

  if readLen > 0:
    discard sysWrite(addr buffer[0], U64(readLen))

  if readLen == 0 or buffer[readLen - 1] != '\n':
    write("\n")

  sysExit(0)
