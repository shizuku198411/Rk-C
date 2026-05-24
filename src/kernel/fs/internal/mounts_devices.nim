## Resolves VFS mount paths and built-in device namespace paths.

## Copies info string.
proc copyInfoString(dst: var array[SysFsInfoNameMax, char], src: cstring) =
  var i = U32(0)
  while i + U32(1) < SysFsInfoNameMax and src[i] != '\0':
    dst[i] = src[i]
    inc i
  while i < SysFsInfoNameMax:
    dst[i] = '\0'
    inc i


## Implements the path matches mount kernel helper.
proc pathMatchesMount(path: cstring, mountPath: cstring, mountLen: int): bool =
  if path == nil or mountPath == nil or mountLen <= 0:
    return false

  var i = 0
  while i < mountLen:
    if path[i] != mountPath[i]:
      return false
    inc i
  path[mountLen] == '\0' or path[mountLen] == '/'


## Implements the mount local path kernel helper.
proc mountLocalPath(path: cstring, mountLen: int): cstring =
  if path[mountLen] == '\0':
    return "/"
  cast[cstring](unsafeAddr path[mountLen])


## Implements the vfs mount kernel helper.
proc vfsMount(path: cstring, backend: VfsBackend) =
  if path == nil or path[0] == '\0':
    panic("invalid vfs mount path")
  if mountCount >= VfsMaxMounts:
    panic("vfs mount table full")

  let idx = mountCount
  discard copyCString(mounts[idx].path, path)
  mounts[idx].pathLen = int(cstrlen(path))
  mounts[idx].backend = backend
  mounts[idx].used = true
  inc mountCount


## Finds mount.
proc findMount(path: cstring): int =
  var best = -1
  var i = 0
  while i < mountCount:
    if mounts[i].used and
        pathMatchesMount(path, cast[cstring](addr mounts[i].path[0]), mounts[i].pathLen):
      if best < 0 or mounts[i].pathLen > mounts[best].pathLen:
        best = i
    inc i
  best


## Clears mounts.
proc clearMounts() =
  var i = 0
  while i < VfsMaxMounts:
    mounts[i] = VfsMount()
    inc i
  mountCount = 0


## Returns whether bin root is true.
proc isBinRoot(path: cstring): bool =
  cstringEq(path, "/bin") or cstringEq(path, "/bin/")


## Returns whether bin path is true.
proc isBinPath(path: cstring): bool =
  if path == nil:
    return false

  isBinRoot(path) or
    (path[0] == '/' and path[1] == 'b' and path[2] == 'i' and
      path[3] == 'n' and path[4] == '/')


## Returns whether dev root is true.
proc isDevRoot(path: cstring): bool =
  cstringEq(path, "/dev") or cstringEq(path, "/dev/")


## Returns whether proc root is true.
proc isProcRoot(path: cstring): bool =
  cstringEq(path, "/proc") or cstringEq(path, "/proc/")


## Returns whether proc path is true.
proc isProcPath(path: cstring): bool =
  if path == nil:
    return false

  isProcRoot(path) or
    (path[0] == '/' and path[1] == 'p' and path[2] == 'r' and
      path[3] == 'o' and path[4] == 'c' and path[5] == '/')


## Resolves dev path.
proc resolveDevPath(path: cstring): int =
  if path == nil or not (path[0] == '/' and path[1] == 'd' and path[2] == 'e' and
      path[3] == 'v' and path[4] == '/'):
    return -1

  let name = cast[cstring](unsafeAddr path[5])
  if name[0] == '\0':
    return -1

  var i = 0
  while i < DevEntryCount:
    if cstringEq(name, devEntryNames[i]):
      return i
    inc i

  -1


