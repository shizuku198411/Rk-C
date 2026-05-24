## Enumerates procfs root, process, and file-descriptor directories.

proc procLsEntryLimit(): U32 =
  var capacity = packet.arg0
  if capacity > U64(SysIpcMessageMax):
    capacity = U64(SysIpcMessageMax)

  U32(capacity div U64(sizeof(DirEntry)))


proc procLsOffset(): U32 =
  U32(packet.arg1)


proc renderLsProcFd(pid: I32): I32 =
  clearResponseData()

  let fdCount = sysFdList(pid, addr fdInfos[0], U64(SysFdMax))
  if fdCount < 0:
    return -1

  let
    maxEntries = procLsEntryLimit()
    offset = procLsOffset()
    entries = cast[ptr UncheckedArray[DirEntry]](addr response.data[0])

  var
    count = U32(0)
    seen = U32(0)

  template addFd(fd: I32) =
    if seen >= offset and count < maxEntries:
      writeFdDirEntry(addr entries[count], fd)
      inc count
    inc seen

  if seen >= offset and count < maxEntries:
    writeDirEntry(addr entries[count], cstring".", DirEntryTypeDir)
    inc count
  inc seen

  if seen >= offset and count < maxEntries:
    writeDirEntry(addr entries[count], cstring"..", DirEntryTypeDir)
    inc count
  inc seen

  var i = U32(0)
  while i < U32(fdCount):
    addFd(fdInfos[i].fd)
    inc i

  response.len = count * U32(sizeof(DirEntry))
  I32(count)


proc renderLsProcRoot(): I32 =
  clearResponseData()

  let maxEntries = procLsEntryLimit()
  let offset = procLsOffset()
  var count = U32(0)
  var seen = U32(0)
  let entries = cast[ptr UncheckedArray[DirEntry]](addr response.data[0])

  template add(name: cstring, typ: U32) =
    if seen >= offset and count < maxEntries:
      writeDirEntry(addr entries[count], name, typ)
      inc count
    inc seen

  add(cstring".", DirEntryTypeDir)
  add(cstring"..", DirEntryTypeDir)

  var staticIndex = 0
  while staticIndex < ProcFsEntryCount:
    add(procEntries[staticIndex], DirEntryTypeFile)
    inc staticIndex

  let procCount = sysPs(addr procInfos[0], U64(SysProcessMaxSlots), SysProcListAllSlots)
  if procCount < 0:
    return -1

  var i = I32(0)
  while i < procCount:
    if procInfos[i].state != SysProcessUnused:
      if seen >= offset and count < maxEntries:
        writePidDirEntry(addr entries[count], procInfos[i].pid)
        inc count
      inc seen
    inc i

  response.len = count * U32(sizeof(DirEntry))
  I32(count)


proc renderLsProcPid(pid: I32): I32 =
  if not processExists(pid):
    return -1

  clearResponseData()
  let maxEntries = procLsEntryLimit()
  let offset = procLsOffset()
  if maxEntries == U32(0):
    response.len = 0
    return 0

  let entries = cast[ptr UncheckedArray[DirEntry]](addr response.data[0])
  var count = U32(0)
  var seen = U32(0)

  template add(name: cstring, typ: U32) =
    if seen >= offset and count < maxEntries:
      writeDirEntry(addr entries[count], name, typ)
      inc count
    inc seen

  add(cstring".", DirEntryTypeDir)
  add(cstring"..", DirEntryTypeDir)
  add(cstring"status", DirEntryTypeFile)
  add(cstring"rkx_map", DirEntryTypeFile)
  add(cstring"fd", DirEntryTypeDir)

  response.len = count * U32(sizeof(DirEntry))
  I32(count)


proc renderLsProc(path: cstring): I32 =
  if cstringEq(path, cstring("/proc")) or cstringEq(path, cstring("/proc/")):
    return renderLsProcRoot()

  var pid = I32(0)
  if parseProcPidPath(path, pid):
    return renderLsProcPid(pid)

  if parseFdDirPath(path, pid):
    return renderLsProcFd(pid)

  -1


