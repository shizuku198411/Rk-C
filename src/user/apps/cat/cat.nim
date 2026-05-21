## Concatenates a file or stdin to stdout.
import ../../lib/core/io
import ../../lib/core/args
import ../../lib/core/pathutils
import ../../lib/core/strutils
import ../../lib/core/syscall

const
  CatBufferSize = 4096

var buffer: array[CatBufferSize, char]
var parsedArgs: UserArgs


## Prints cat usage information.
proc printUsage() =
  write("usage: cat [path]\n")


## Streams stdin to stdout until EOF.
proc catStdin() =
  while true:
    let readLen = sysReadFd(0, addr buffer[0], U64(CatBufferSize))
    if readLen < 0:
      write("cat: failed\n")
      sysExit(1)
    if readLen == 0:
      break

    discard sysWriteFd(1, addr buffer[0], U64(readLen))


## Parses arguments and prints stdin or one resolved file path.
proc user_start*(arg: cstring) {.exportc, cdecl, noreturn.} =
  discard parseUserArgs(arg, parsedArgs)

  if parsedArgs.argc == 1 and cstringEq(argAt(parsedArgs, 0), "--help"):
    printUsage()
    sysExit(0)

  if parsedArgs.argc == 0:
    catStdin()
    sysExit(0)

  if parsedArgs.argc != 1:
    printUsage()
    sysExit(1)

  let path = resolvePath(argAt(parsedArgs, 0))
  if path == nil:
    write("cat: path too long\n")
    sysExit(1)

  let readLen = sysReadFile(path, addr buffer[0], U64(CatBufferSize))
  if readLen < 0:
    write("cat: failed\n")
    sysExit(1)

  if readLen > 0:
    discard sysWrite(addr buffer[0], U64(readLen))

  if readLen == 0 or buffer[readLen - 1] != '\n':
    write("\n")

  sysExit(0)
