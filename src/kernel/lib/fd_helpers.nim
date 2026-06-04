## Provides helpers for process file descriptor lookup and validation.
import ../../lib/fixed_string
import ../../lib/syscall_types
import ../../lib/types
import ../dev/tty
import ../task/process


## Copies fd path.
proc copyFdPath*(entry: var FdEntry, path: cstring) =
  discard copyCString(entry.path, path)


## Implements the fd path kernel helper.
proc fdPath*(entry: var FdEntry): cstring =
  cast[cstring](addr entry.path[0])


## Implements the device kind for path kernel helper.
proc deviceKindForPath*(path: cstring): U32 =
  if cstringEq(path, "/dev/stdin") or cstringEq(path, "/dev/stdout") or
      cstringEq(path, "/dev/stderr") or cstringEq(path, "/dev/console") or
      cstringEq(path, "/dev/tty0"):
    return SysFdKindTty

  SysFdKindFile


## Returns the TTY device identifier associated with a device path.
proc ttyIdForPath*(path: cstring): I32 =
  if deviceKindForPath(path) == SysFdKindTty:
    return Tty0Id

  -1


## Returns whether open flags are valid for a TTY alias path.
proc ttyPathAllowsFlags*(path: cstring, flags: U32): bool =
  if cstringEq(path, "/dev/stdin"):
    return (flags and SysOpenRead) != U32(0) and (flags and SysOpenWrite) == U32(0)
  if cstringEq(path, "/dev/stdout") or cstringEq(path, "/dev/stderr"):
    return (flags and SysOpenWrite) != U32(0) and (flags and SysOpenRead) == U32(0)
  if cstringEq(path, "/dev/console") or cstringEq(path, "/dev/tty0"):
    return (flags and (SysOpenRead or SysOpenWrite)) != U32(0)

  false


## Returns whether fd is valid.
proc validFd*(fd: I32): bool =
  fd >= 0 and fd < I32(SysFdMax) and currentProc != nil and
    currentProc.files.entries[U32(fd)].used


## Allocates fd.
proc allocFd*(first: U32 = 3): I32 =
  if currentProc == nil:
    return -1

  var i = first
  while i < SysFdMax:
    if not currentProc.files.entries[i].used:
      return I32(i)
    inc i

  -1


## Finds free fd.
proc findFreeFd*(exclude: I32 = -1, first: U32 = 3): I32 =
  if currentProc == nil:
    return -1

  var i = first
  while i < SysFdMax:
    if I32(i) != exclude and not currentProc.files.entries[i].used:
      return I32(i)
    inc i

  -1
