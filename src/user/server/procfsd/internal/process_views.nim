## Parses process paths and renders per-process procfs views.

proc parseProcChildPath(path: cstring, child: cstring, pid: var I32): bool =
  if not (path[0] == '/' and path[1] == 'p' and path[2] == 'r' and
      path[3] == 'o' and path[4] == 'c' and path[5] == '/'):
    return false

  var i = 6
  var value = I32(0)
  if path[i] < '0' or path[i] > '9':
    return false

  while path[i] >= '0' and path[i] <= '9':
    value = value * I32(10) + I32(ord(path[i]) - ord('0'))
    inc i

  if path[i] != '/':
    return false

  inc i
  var j = 0
  while child[j] != '\0':
    if path[i + j] != child[j]:
      return false
    inc j

  if path[i + j] != '\0':
    return false

  pid = value
  true


proc parseStatusPath(path: cstring, pid: var I32): bool =
  parseProcChildPath(path, cstring"status", pid)


proc parseRkxMapPath(path: cstring, pid: var I32): bool =
  parseProcChildPath(path, cstring"rkx_map", pid)


proc parseFdDirPath(path: cstring, pid: var I32): bool =
  parseProcChildPath(path, cstring"fd", pid)


proc parseFdEntryPath(path: cstring, pid: var I32, fd: var I32): bool =
  if not (path[0] == '/' and path[1] == 'p' and path[2] == 'r' and
      path[3] == 'o' and path[4] == 'c' and path[5] == '/'):
    return false

  var
    i = 6
    pidValue = I32(0)
  if path[i] < '0' or path[i] > '9':
    return false

  while path[i] >= '0' and path[i] <= '9':
    pidValue = pidValue * I32(10) + I32(ord(path[i]) - ord('0'))
    inc i

  if path[i] != '/':
    return false
  inc i

  if path[i] != 'f' or path[i + 1] != 'd' or path[i + 2] != '/':
    return false
  i += 3

  var fdValue = I32(0)
  if path[i] < '0' or path[i] > '9':
    return false

  while path[i] >= '0' and path[i] <= '9':
    fdValue = fdValue * I32(10) + I32(ord(path[i]) - ord('0'))
    inc i

  if path[i] != '\0':
    return false

  pid = pidValue
  fd = fdValue
  true


proc writeFdDirEntry(entry: ptr DirEntry, fd: I32) =
  entry.typ = DirEntryTypeFile
  entry.size = 0

  var
    tmp: array[16, char]
    n = fd
    i = 0

  if n == 0:
    entry.name[0] = '0'
    entry.name[1] = '\0'
    return

  while n > 0 and i < 16:
    tmp[i] = char(ord('0') + (n mod I32(10)))
    n = n div I32(10)
    inc i

  var pos = 0
  while i > 0 and pos + 1 < DirEntryNameMax:
    dec i
    entry.name[pos] = tmp[i]
    inc pos

  entry.name[pos] = '\0'


proc parseProcPidPath(path: cstring, pid: var I32): bool =
  if not (path[0] == '/' and path[1] == 'p' and path[2] == 'r' and
      path[3] == 'o' and path[4] == 'c' and path[5] == '/'):
    return false

  var i = 6
  var value = I32(0)
  if path[i] < '0' or path[i] > '9':
    return false

  while path[i] >= '0' and path[i] <= '9':
    value = value * I32(10) + I32(ord(path[i]) - ord('0'))
    inc i

  if not (path[i] == '\0' or (path[i] == '/' and path[i + 1] == '\0')):
    return false

  pid = value
  true


proc processExists(pid: I32): bool =
  let count = sysPs(addr procInfos[0], U64(SysProcessMaxSlots), SysProcListAllSlots)
  if count < 0:
    return false

  var i = I32(0)
  while i < count:
    if procInfos[i].state != SysProcessUnused and procInfos[i].pid == pid:
      return true
    inc i

  false


proc renderStatus(pid: I32): U32 =
  clearOut()
  var pos = U32(0)

  let count = sysPs(addr procInfos[0], U64(SysProcessMaxSlots), SysProcListAllSlots)
  if count < 0:
    appendStr(pos, cstring("error\n"))
    return pos

  var i = I32(0)
  while i < count:
    if procInfos[i].state != SysProcessUnused and procInfos[i].pid == pid:
      appendStr(pos, cstring("pid: "))
      appendI32(pos, procInfos[i].pid)
      appendChar(pos, '\n')

      appendStr(pos, cstring("ppid: "))
      appendI32(pos, procInfos[i].ppid)
      appendChar(pos, '\n')

      appendStr(pos, cstring("uid: "))
      appendU64(pos, U64(procInfos[i].uid))
      appendChar(pos, '\n')

      appendStr(pos, cstring("gid: "))
      appendU64(pos, U64(procInfos[i].gid))
      appendChar(pos, '\n')

      appendStr(pos, cstring("state: "))
      appendStr(pos, stateName(procInfos[i].state))
      appendChar(pos, '\n')

      appendStr(pos, cstring("mode: "))
      appendStr(pos, userName(procInfos[i].isUser))
      appendChar(pos, '\n')

      appendStr(pos, cstring("cpu_ticks: "))
      appendU64(pos, procInfos[i].cpuTicks)
      appendChar(pos, '\n')

      appendStr(pos, cstring("cpu: "))
      appendPercent(pos, procInfos[i].cpuPercent)
      appendChar(pos, '\n')

      appendStr(pos, cstring("mem: "))
      appendPages(pos, procInfos[i].memoryPages)
      appendChar(pos, '\n')

      appendCapMaskLine(pos, cstring("requested_caps"), procInfos[i].requestedCapabilityMask)
      appendCapMaskLine(pos, cstring("caps"), procInfos[i].capabilityMask)
      appendSignalMaskLine(pos, cstring("pending_signals"), procInfos[i].pendingSignals)

      appendStr(pos, cstring("exe: "))
      appendStr(pos, cast[cstring](addr procInfos[i].exePath[0]))
      appendChar(pos, '\n')
      return pos
    inc i

  appendStr(pos, cstring("not found\n"))
  pos


proc renderRkxMap(pid: I32): U32 =
  clearOut()
  var pos = U32(0)

  let count = sysPs(addr procInfos[0], U64(SysProcessMaxSlots), SysProcListAllSlots)
  if count < 0:
    appendStr(pos, cstring("error\n"))
    return pos

  var i = I32(0)
  while i < count:
    if procInfos[i].state != SysProcessUnused and procInfos[i].pid == pid:
      if procInfos[i].isUser == 0:
        appendStr(pos, cstring("not rkx user process\n"))
        return pos

      appendRkxMapLine(pos, procInfos[i].textVa, procInfos[i].textMemSize, cstring"r-x", cstring"text")
      appendRkxMapLine(pos, procInfos[i].rodataVa, procInfos[i].rodataMemSize, cstring"r--", cstring"rodata")
      appendRkxMapLine(pos, procInfos[i].dataVa, procInfos[i].dataMemSize, cstring"rw-", cstring"data")
      appendRkxMapLine(pos, procInfos[i].bssVa, procInfos[i].bssMemSize, cstring"rw-", cstring"bss")
      appendRkxMapLine(
        pos,
        procInfos[i].stackTop - procInfos[i].stackPages * ProcFsPageSize,
        procInfos[i].stackPages * ProcFsPageSize,
        cstring"rw-",
        cstring"stack",
      )
      if procInfos[i].heapPages != 0:
        appendRkxMapLine(
          pos,
          procInfos[i].heapStart,
          procInfos[i].heapPages * ProcFsPageSize,
          cstring"rw-",
          cstring"heap",
        )
      return pos
    inc i

  appendStr(pos, cstring("not found\n"))
  pos


