## Copies one file to another path.
import ../../lib/core/io
import ../../lib/core/args
import ../../lib/core/app
import ../../lib/core/syscall
import ../../lib/core/pathutils

const buffSize = 4096

var
  parsedArgs: UserArgs
  buffer: array[buffSize, char]
  srcPathBuf: array[PathMax, char]
  dstPathBuf: array[PathMax, char]


## Prints cp usage information.
proc printUsage() =
  write("usage: cp <srcpath> <dstpath>\n")


## Copies file content through descriptors so files larger than one syscall chunk are supported.
proc copyFile(srcPath, dstPath: cstring): bool =
  let srcFd = sysOpen(srcPath, SysOpenRead)
  if srcFd < 0:
    return false

  let dstFd = sysOpen(dstPath, SysOpenWrite or SysOpenCreate or SysOpenTrunc)
  if dstFd < 0:
    discard sysClose(srcFd)
    return false

  var ok = true
  while true:
    let readLen = sysReadFd(srcFd, addr buffer[0], U64(buffSize))
    if readLen < 0:
      ok = false
      break
    if readLen == 0:
      break
    if sysWriteFd(dstFd, addr buffer[0], U64(readLen)) != readLen:
      ok = false
      break

  discard sysClose(srcFd)
  discard sysClose(dstFd)
  ok


## Parses source and destination paths, then copies file contents.
proc user_start*(arg: cstring) {.exportc, cdecl, noreturn.} =
  parseArgsOrExit(arg, parsedArgs, printUsage)
  exitIfHelp(parsedArgs, printUsage)
  requireArgc(parsedArgs, U32(2), printUsage)
  
  let
    srcPath = resolvePathInto(argAt(parsedArgs, 0), srcPathBuf)
    dstPath = resolvePathInto(argAt(parsedArgs, 1), dstPathBuf)
  if srcPath == nil or dstPath == nil:
    write("path too long\n")
    sysExit(1)
  
  if not copyFile(srcPath, dstPath):
    write("failed to copy file\n")
    sysExit(1)

  sysExit(0)
