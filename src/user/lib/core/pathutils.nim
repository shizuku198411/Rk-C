import ./syscall
import ./strutils

const
  PathMax* = 128

var resolvedPath: array[PathMax, char]


proc copyCString(dst: var array[PathMax, char], pos: var U64, src: cstring): bool =
  var i = U64(0)
  while src[i] != '\0':
    if pos + 1 >= U64(PathMax):
      return false
    dst[pos] = src[i]
    inc pos
    inc i
  true


proc terminate(dst: var array[PathMax, char], pos: U64) =
  if pos < U64(PathMax):
    dst[pos] = '\0'


proc resolvePath*(path: cstring): cstring =
  if isEmpty(path):
    let rc = sysGetCwd(addr resolvedPath[0], U64(PathMax))
    if rc < 0:
      resolvedPath[0] = '/'
      resolvedPath[1] = '\0'
    return cast[cstring](addr resolvedPath[0])

  if path[0] == '/':
    return path

  var cwd: array[SysProcessCwdMax, char]
  if sysGetCwd(addr cwd[0], U64(SysProcessCwdMax)) < 0:
    cwd[0] = '/'
    cwd[1] = '\0'

  var pos = U64(0)
  if not copyCString(resolvedPath, pos, cast[cstring](addr cwd[0])):
    return nil

  if pos > 0 and resolvedPath[pos - 1] != '/':
    if pos + 1 >= U64(PathMax):
      return nil
    resolvedPath[pos] = '/'
    inc pos

  if not copyCString(resolvedPath, pos, path):
    return nil

  terminate(resolvedPath, pos)
  cast[cstring](addr resolvedPath[0])
