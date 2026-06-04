## Renders open file-descriptor information for procfs.

proc fdKindName(kind: U32): cstring =
  if kind == SysFdKindFile:
    cstring"file"
  elif kind == SysFdKindStdin:
    cstring"stdin"
  elif kind == SysFdKindStdout:
    cstring"stdout"
  elif kind == SysFdKindStderr:
    cstring"stderr"
  elif kind == SysFdKindConsole:
    cstring"console"
  elif kind == SysFdKindPipe:
    cstring"pipe"
  elif kind == SysFdKindTty:
    cstring"tty"
  else:
    cstring"unknown"


proc appendFdFlags(pos: var U32, flags: U32) =
  var first = true

  if (flags and SysOpenRead) != 0:
    appendStr(pos, cstring"read")
    first = false

  if (flags and SysOpenWrite) != 0:
    if not first:
      appendChar(pos, ',')
    appendStr(pos, cstring"write")
    first = false

  if (flags and SysOpenAppend) != 0:
    if not first:
      appendChar(pos, ',')
    appendStr(pos, cstring"append")
    first = false

  if first:
    appendStr(pos, cstring"none")


proc renderFdInfo(pid, fd: I32): U32 =
  clearOut()
  var pos = U32(0)

  let fdCount = sysFdList(pid, addr fdInfos[0], U64(SysFdMax))
  if fdCount < 0:
    appendStr(pos, cstring"not found\n")
    return pos

  var i = U32(0)
  while i < U32(fdCount):
    if fdInfos[i].fd == fd:
      appendStr(pos, cstring"fd: ")
      appendI32(pos, fdInfos[i].fd)
      appendChar(pos, '\n')

      appendStr(pos, cstring"kind: ")
      appendStr(pos, fdKindName(fdInfos[i].kind))
      appendChar(pos, '\n')

      appendStr(pos, cstring"flags: ")
      appendFdFlags(pos, fdInfos[i].flags)
      appendChar(pos, '\n')

      appendStr(pos, cstring"offset: ")
      appendU64(pos, fdInfos[i].offset)
      appendChar(pos, '\n')

      appendStr(pos, cstring"size: ")
      appendU64(pos, fdInfos[i].size)
      appendChar(pos, '\n')

      if fdInfos[i].kind == SysFdKindPipe:
        appendStr(pos, cstring"pipe_id: ")
        appendI32(pos, fdInfos[i].pipeId)
        appendChar(pos, '\n')

      if fdInfos[i].kind == SysFdKindTty:
        appendStr(pos, cstring"tty_id: ")
        appendI32(pos, fdInfos[i].ttyId)
        appendChar(pos, '\n')

      appendStr(pos, cstring"path: ")
      appendStr(pos, cast[cstring](addr fdInfos[i].path[0]))
      appendChar(pos, '\n')

      return pos

    inc i

  appendStr(pos, cstring"not found\n")
  pos

