import ../../lib/core/io
import ../../lib/core/args
import ../../lib/core/syscall
import ../../lib/core/pathutils
import ../../lib/core/strutils

const buffSize = 4096

var
  parsedArgs: UserArgs
  buffer: array[buffSize, char]
  srcPathBuf: array[PathMax, char]
  dstPathBuf: array[PathMax, char]


proc printUsage() =
  write("usage: cp <srcpath> <dstpath>\n")


proc user_start*(arg: cstring) {.exportc, cdecl, noreturn.} =
  if not parseUserArgs(arg, parsedArgs):
    printUsage()
    sysExit(1)

  if parsedArgs.argc == 1 and cstringEq(argAt(parsedArgs, 0), "--help"):
    printUsage()
    sysExit(0)
  
  if parsedArgs.argc != 2:
    printUsage()
    sysExit(1)
  
  let
    srcPath = resolvePathInto(argAt(parsedArgs, 0), srcPathBuf)
    dstPath = resolvePathInto(argAt(parsedArgs, 1), dstPathBuf)
  if srcPath == nil or dstPath == nil:
    write("path too long\n")
    sysExit(1)
  
  let srcLen = sysReadFile(srcPath, addr buffer[0], U64(buffSize))
  if srcLen < 0:
    write("failed to read file\n")
    sysExit(1)
  
  if sysWriteFile(dstPath, addr buffer[0], U64(srcLen)) != 0:
    write("failed to write file\n")
    sysExit(1)

  sysExit(0)
