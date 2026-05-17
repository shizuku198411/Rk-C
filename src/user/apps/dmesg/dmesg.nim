import ../../lib/core/args
import ../../lib/core/io
import ../../lib/core/strutils
import ../../lib/core/syscall

const
  DmesgBufferSize = int(SysKmsgMax)

var
  buffer: array[DmesgBufferSize, char]
  parsedArgs: UserArgs


proc printUsage() =
  write("usage: dmesg\n")


proc user_start*(arg: cstring) {.exportc, cdecl, noreturn.} =
  discard parseUserArgs(arg, parsedArgs)

  if parsedArgs.argc == 1 and streq(argAt(parsedArgs, 0), "--help"):
    printUsage()
    sysExit(0)

  if parsedArgs.argc != 0:
    printUsage()
    sysExit(1)

  let n = sysKmsg(addr buffer[0], U64(SysKmsgMax))
  if n < 0:
    write("dmesg: failed\n")
    sysExit(1)

  if n > 0:
    discard sysWriteFd(1, addr buffer[0], U64(n))
    if buffer[int(n - 1)] != '\n':
      write("\n")

  sysExit(0)
