## Prints kernel message log contents.
import ../../lib/core/args
import ../../lib/core/app
import ../../lib/core/io
import ../../lib/core/syscall

const
  DmesgBufferSize = int(SysKmsgMax)

var
  buffer: array[DmesgBufferSize, char]
  parsedArgs: UserArgs


## Prints dmesg usage information.
proc printUsage() =
  write("usage: dmesg\n")


## Reads the kernel log buffer and writes it to stdout.
proc user_start*(arg: cstring) {.exportc, cdecl, noreturn.} =
  parseArgsOrExit(arg, parsedArgs, printUsage)
  exitIfHelp(parsedArgs, printUsage)
  requireArgc(parsedArgs, U32(0), printUsage)

  let n = sysKmsg(addr buffer[0], U64(SysKmsgMax))
  if n < 0:
    write("dmesg: failed\n")
    sysExit(1)

  if n > 0:
    discard sysWriteFd(1, addr buffer[0], U64(n))
    if buffer[int(n - 1)] != '\n':
      write("\n")

  sysExit(0)
