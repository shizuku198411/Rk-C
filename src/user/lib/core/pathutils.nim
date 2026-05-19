import ./syscall
import ./strutils

const
  PathMax* = 128

var resolvedPath: array[PathMax, char]
var joinedPath: array[PathMax, char]


proc copyCString(dst: var openArray[char], src: cstring): bool =
  if dst.len == 0:
    return false

  var i = 0
  while i + 1 < dst.len and src[i] != '\0':
    dst[i] = src[i]
    inc i

  if src[i] != '\0':
    return false

  while i < dst.len:
    dst[i] = '\0'
    inc i

  true


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


proc clearPath(dst: var array[PathMax, char]) =
  var i = 0
  while i < PathMax:
    dst[i] = '\0'
    inc i


proc appendChar(dst: var array[PathMax, char], pos: var U64, ch: char): bool =
  if pos + 1 >= U64(PathMax):
    return false

  dst[pos] = ch
  inc pos
  dst[pos] = '\0'
  true


proc popComponent(dst: var array[PathMax, char], pos: var U64) =
  if pos <= U64(1):
    pos = U64(1)
    dst[0] = '/'
    dst[1] = '\0'
    return

  if dst[pos - U64(1)] == '/':
    dec pos

  while pos > U64(1) and dst[pos - U64(1)] != '/':
    dec pos

  if pos == U64(0):
    pos = U64(1)
  dst[pos] = '\0'


proc appendComponent(dst: var array[PathMax, char], pos: var U64, src: cstring,
                     startPos, endPos: int): bool =
  let len = endPos - startPos
  if len == 0:
    return true
  if len == 1 and src[startPos] == '.':
    return true
  if len == 2 and src[startPos] == '.' and src[startPos + 1] == '.':
    popComponent(dst, pos)
    return true

  if pos == U64(0):
    if not appendChar(dst, pos, '/'):
      return false
  elif dst[pos - U64(1)] != '/':
    if not appendChar(dst, pos, '/'):
      return false

  var i = startPos
  while i < endPos:
    if not appendChar(dst, pos, src[i]):
      return false
    inc i

  true


proc normalizeAbsolute(path: cstring): cstring =
  clearPath(resolvedPath)
  var pos = U64(0)
  if not appendChar(resolvedPath, pos, '/'):
    return nil

  var i = 0
  while path[i] != '\0':
    while path[i] == '/':
      inc i

    let start = i
    while path[i] != '\0' and path[i] != '/':
      inc i

    if not appendComponent(resolvedPath, pos, path, start, i):
      return nil

  if pos > U64(1) and resolvedPath[pos - U64(1)] == '/':
    dec pos
  terminate(resolvedPath, pos)
  cast[cstring](addr resolvedPath[0])


proc resolvePath*(path: cstring): cstring =
  if isEmpty(path):
    let rc = sysGetCwd(addr resolvedPath[0], U64(PathMax))
    if rc < 0:
      resolvedPath[0] = '/'
      resolvedPath[1] = '\0'
    return cast[cstring](addr resolvedPath[0])

  if path[0] == '/':
    return normalizeAbsolute(path)

  var cwd: array[SysProcessCwdMax, char]
  if sysGetCwd(addr cwd[0], U64(SysProcessCwdMax)) < 0:
    cwd[0] = '/'
    cwd[1] = '\0'

  var pos = U64(0)
  clearPath(joinedPath)
  if not copyCString(joinedPath, pos, cast[cstring](addr cwd[0])):
    return nil

  if pos > 0 and joinedPath[pos - 1] != '/':
    if pos + 1 >= U64(PathMax):
      return nil
    joinedPath[pos] = '/'
    inc pos

  if not copyCString(joinedPath, pos, path):
    return nil

  terminate(joinedPath, pos)
  normalizeAbsolute(cast[cstring](addr joinedPath[0]))


proc resolvePathInto*(path: cstring, dst: var openArray[char]): cstring =
  let resolved = resolvePath(path)
  if resolved == nil:
    return nil
  if not copyCString(dst, resolved):
    return nil

  cast[cstring](addr dst[0])
