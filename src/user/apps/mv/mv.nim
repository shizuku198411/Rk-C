import ../../lib/core/io
import ../../lib/core/args
import ../../lib/core/syscall
import ../../lib/core/pathutils
import ../../lib/core/strutils

const
  MvMaxEntries = 2

var
  parsedArgs: UserArgs
  entries: array[MvMaxEntries, DirEntry]
  srcPathBuf: array[PathMax, char]
  dstPathBuf: array[PathMax, char]
  targetPathBuf: array[PathMax, char]


proc printUsage() =
  write("usage: mv <src>... <dst>\n")


proc clearPath(dst: var array[PathMax, char]) =
  var i = 0
  while i < PathMax:
    dst[i] = '\0'
    inc i


proc copyChar(dst: var array[PathMax, char], pos: var int, ch: char): bool =
  if pos + 1 >= PathMax:
    return false

  dst[pos] = ch
  inc pos
  dst[pos] = '\0'
  true


proc isDir(path: cstring): bool =
  let count = sysLs(path, addr entries[0], U64(MvMaxEntries))
  if count < 0:
    return false

  entries[0].typ == DirEntryTypeDir or entries[0].typ == DirEntryTypeMount


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


proc moveOne(srcPath, dstPath: cstring): bool =
  sysRename(srcPath, dstPath) == 0


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
