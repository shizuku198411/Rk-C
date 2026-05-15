import ../../lib/fixed_string
import ../../lib/syscall_types
import ../../lib/types
import ../task/process


proc copyFdPath*(entry: var FdEntry, path: cstring) =
  discard copyCString(entry.path, path)


proc fdPath*(entry: var FdEntry): cstring =
  cast[cstring](addr entry.path[0])


proc deviceKindForPath*(path: cstring): U32 =
  if cstringEq(path, "/dev/stdin"):
    return SysFdKindStdin
  if cstringEq(path, "/dev/stdout"):
    return SysFdKindStdout
  if cstringEq(path, "/dev/stderr"):
    return SysFdKindStderr
  if cstringEq(path, "/dev/console"):
    return SysFdKindConsole

  SysFdKindFile


proc validFd*(fd: I32): bool =
  fd >= 0 and fd < I32(SysFdMax) and currentProc != nil and
    currentProc.files.entries[U32(fd)].used


proc allocFd*(first: U32 = 3): I32 =
  if currentProc == nil:
    return -1

  var i = first
  while i < SysFdMax:
    if not currentProc.files.entries[i].used:
      return I32(i)
    inc i

  -1


proc findFreeFd*(exclude: I32 = -1, first: U32 = 3): I32 =
  if currentProc == nil:
    return -1

  var i = first
  while i < SysFdMax:
    if I32(i) != exclude and not currentProc.files.entries[i].used:
      return I32(i)
    inc i

  -1
