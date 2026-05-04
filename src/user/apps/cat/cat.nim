import ../../lib/io
import ../../lib/strutils
import ../../lib/syscall

const
  CatBufferSize = 4096

var buffer: array[CatBufferSize, char]

proc user_start*(arg: cstring) {.exportc, cdecl, noreturn.} =
  if isEmpty(arg):
    write("usage: cat <path>\n")
    sysExit(1)

  let readLen = sysReadFile(arg, addr buffer[0], U64(CatBufferSize))
  if readLen < 0:
    write("cat: failed\n")
    sysExit(1)

  if readLen > 0:
    discard sysWrite(addr buffer[0], U64(readLen))

  if readLen == 0 or buffer[readLen - 1] != '\n':
    write("\n")

  sysExit(0)
