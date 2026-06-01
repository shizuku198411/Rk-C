## Moves or renames files, with simple copy/unlink fallback.
import ../../lib/core/io
import ../../lib/core/args
import ../../lib/core/app
import ../../lib/core/syscall
import ../../lib/core/path_buffer
import ../../lib/core/pathutils

const
  MvMaxEntries = 2
  MoveBufferSize = 4096

var
  parsedArgs: UserArgs
  entries: array[MvMaxEntries, DirEntry]
  moveBuffer: array[MoveBufferSize, char]
  srcPathBuf: array[PathMax, char]
  dstPathBuf: array[PathMax, char]
  targetPathBuf: array[PathMax, char]


## Prints mv usage information.
proc printUsage() =
  write("usage: mv <src>... <dst>\n")


## Returns true when a path can be listed as a directory.
proc isDir(path: cstring): bool =
  let count = sysLs(path, addr entries[0], U64(MvMaxEntries))
  count >= 0


## Moves one source path to one target path.
proc moveOne(srcPath, dstPath: cstring): bool =
  if sysRename(srcPath, dstPath) == 0:
    return true

  if isDir(dstPath):
    return false

  let existingLen = sysReadFile(dstPath, addr moveBuffer[0], U64(1))
  if existingLen >= 0:
    return false

  let srcLen = sysReadFile(srcPath, addr moveBuffer[0], U64(MoveBufferSize))
  if srcLen < 0:
    return false

  if sysWriteFileMode(dstPath, addr moveBuffer[0], U64(srcLen), SysFsWriteCreate or SysFsWriteOverwrite) != 0:
    return false

  sysUnlink(srcPath) == 0


## Parses mv arguments and moves each source to the destination.
proc user_start*(arg: cstring) {.exportc, cdecl, noreturn.} =
  parseArgsOrExit(arg, parsedArgs, printUsage)
  exitIfHelp(parsedArgs, printUsage)
  requireMinArgc(parsedArgs, U32(2), printUsage)

  let dstPath = resolvePathInto(argAt(parsedArgs, parsedArgs.argc - U32(1)), dstPathBuf)
  if dstPath == nil:
    write("mv: path too long\n")
    sysExit(1)

  let dstIsDir = isDir(dstPath)
  if parsedArgs.argc > 2 and not dstIsDir:
    write("mv: destination is not a directory\n")
    sysExit(1)

  var i = U32(0)
  while i + U32(1) < parsedArgs.argc:
    let srcPath = resolvePathInto(argAt(parsedArgs, i), srcPathBuf)
    if srcPath == nil:
      write("mv: path too long\n")
      sysExit(1)

    let target =
      if dstIsDir:
        joinPath(
          dstPath,
          pathBasename(srcPath),
          cast[ptr UncheckedArray[char]](addr targetPathBuf[0]),
          PathMax,
        )
      else:
        dstPath
    if target == nil:
      write("mv: path too long\n")
      sysExit(1)

    if not moveOne(srcPath, target):
      write("mv: failed\n")
      sysExit(1)

    inc i

  sysExit(0)
