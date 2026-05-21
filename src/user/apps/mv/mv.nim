## Moves or renames files, with simple copy/unlink fallback.
import ../../lib/core/io
import ../../lib/core/args
import ../../lib/core/syscall
import ../../lib/core/pathutils
import ../../lib/core/strutils

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


## Clears a path buffer.
proc clearPath(dst: var array[PathMax, char]) =
  var i = 0
  while i < PathMax:
    dst[i] = '\0'
    inc i


## Appends one character to a path buffer with bounds checking.
proc copyChar(dst: var array[PathMax, char], pos: var int, ch: char): bool =
  if pos + 1 >= PathMax:
    return false

  dst[pos] = ch
  inc pos
  dst[pos] = '\0'
  true


## Returns true when a path can be listed as a directory.
proc isDir(path: cstring): bool =
  let count = sysLs(path, addr entries[0], U64(MvMaxEntries))
  count >= 0


## Returns a C string view of the final path component.
proc basename(path: cstring): cstring =
  var endPos = 0
  while path[endPos] != '\0':
    inc endPos

  while endPos > 1 and path[endPos - 1] == '/':
    dec endPos

  var start = endPos
  while start > 0 and path[start - 1] != '/':
    dec start

  cast[cstring](addr path[start])


## Joins a directory and basename into a destination path buffer.
proc joinPath(dir, name: cstring, dst: var array[PathMax, char]): cstring =
  clearPath(dst)
  var pos = 0

  if dir[0] == '/' and dir[1] == '\0':
    if not copyChar(dst, pos, '/'):
      return nil
  else:
    var i = 0
    while dir[i] != '\0':
      if not copyChar(dst, pos, dir[i]):
        return nil
      inc i

    if pos > 0 and dst[pos - 1] != '/':
      if not copyChar(dst, pos, '/'):
        return nil

  var i = 0
  while name[i] != '\0':
    if name[i] == '/':
      break
    if not copyChar(dst, pos, name[i]):
      return nil
    inc i

  cast[cstring](addr dst[0])


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
  if not parseUserArgs(arg, parsedArgs):
    printUsage()
    sysExit(1)

  if parsedArgs.argc == 1 and cstringEq(argAt(parsedArgs, 0), "--help"):
    printUsage()
    sysExit(0)

  if parsedArgs.argc < 2:
    printUsage()
    sysExit(1)

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
        joinPath(dstPath, basename(srcPath), targetPathBuf)
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
