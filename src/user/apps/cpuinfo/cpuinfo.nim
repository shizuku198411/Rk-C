## Prints CPU and runtime scheduler information from procfs.
import ../../lib/core/args
import ../../lib/core/app
import ../../lib/core/io
import ../../lib/core/syscall


const CpuInfoBufferSize = 1024

var
  parsedArgs: UserArgs
  buffer: array[CpuInfoBufferSize, char]


## Prints cpuinfo usage information.
proc printUsage() =
  write("usage: cpuinfo\n")
  write("       cpuinfo --help\n")


## Reads /proc/cpuinfo and writes the result to stdout.
proc user_start*(arg: cstring) {.exportc, cdecl, noreturn.} =
  parseArgsOrExit(arg, parsedArgs, printUsage)
  exitIfHelp(parsedArgs, printUsage)
  requireArgc(parsedArgs, U32(0), printUsage)

  let readLen = sysReadFile(cstring"/proc/cpuinfo", addr buffer[0], U64(CpuInfoBufferSize))
  if readLen < 0:
    write("cpuinfo: failed to read /proc/cpuinfo\n")
    sysExit(1)

  if readLen > 0:
    discard sysWrite(addr buffer[0], U64(readLen))

  if readLen == 0 or buffer[readLen - 1] != '\n':
    write("\n")

  sysExit(0)
