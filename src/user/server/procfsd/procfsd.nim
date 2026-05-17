import ../../lib/core/io
import ../../lib/core/syscall
import ../../lib/core/strutils
import ../lib/service_ready


const
  ProcFsBufSize = U32(SysIpcMessageMax)
  ProcFsEntryCount = 6


let procEntries = [
  cstring("uptime"),
  cstring("meminfo"),
  cstring("cpuinfo"),
  cstring("processes"),
  cstring("services"),
  cstring("traps"),
]

var
  packet: SysIpcPacket
  response: SysIpcPacket
  outBuf: array[ProcFsBufSize, char]
  procInfos: array[I32(SysProcessMaxSlots), SysProcessInfo]
  services: array[8, SysServiceInfo]
  traps: SysTrapCount
  bitmap: SysBitmapInfo
  cpuInfo: SysCpuInfo


proc clearOut() =
  var i = U32(0)
  while i < ProcFsBufSize:
    outBuf[i] = '\0'
    inc i


proc appendChar(pos: var U32, ch: char) =
  if pos + U32(1) < ProcFsBufSize:
    outBuf[pos] = ch
    inc pos
    outBuf[pos] = '\0'


proc appendStr(pos: var U32, s: cstring) =
  var i = U32(0)
  while s[i] != '\0':
    appendChar(pos, s[i])
    inc i


proc appendU64(pos: var U32, value: U64) =
  var
    tmp: array[32, char]
    n = value
    i = 0
  
  if n == 0:
    appendChar(pos, '0')
    return

  while n > 0 and i < 32:
    tmp[i] = char(ord('0') + int(n mod U64(10)))
    n = n div U64(10)
    inc i
  
  while i > 0:
    dec i
    appendChar(pos, tmp[i])


proc appendI32(pos: var U32, value: I32) =
  if value < 0:
    appendChar(pos, '-')
    appendU64(pos, U64(-value))
  else:
    appendU64(pos, U64(value))


proc appendPercent(pos: var U32, value: U32) =
  appendU64(pos, U64(value))
  appendChar(pos, '%')


proc appendPages(pos: var U32, value: U64) =
  appendU64(pos, value)
  appendChar(pos, 'p')


proc clearResponseData() =
  var i = U32(0)
  while i < SysIpcMessageMax:
    response.data[i] = '\0'
    inc i


proc writeDirEntry(entry: ptr DirEntry, name: cstring, typ: U32) =
  entry.typ = typ
  entry.size = 0

  var i = 0
  while i + 1 < DirEntryNameMax and name[i] != '\0':
    entry.name[i] = name[i]
    inc i

  entry.name[i] = '\0'


proc writePidDirEntry(entry: ptr DirEntry, pid: I32) =
  entry.typ = DirEntryTypeDir
  entry.size = 0

  var tmp: array[16, char]
  var n = pid
  var i = 0

  if n <= 0:
    entry.name[0] = '0'
    entry.name[1] = '\0'
    return

  while n > 0 and i < 16:
    tmp[i] = char(ord('0') + int(n mod I32(10)))
    n = n div I32(10)
    inc i

  var pos = 0
  while i > 0 and pos + 1 < DirEntryNameMax:
    dec i
    entry.name[pos] = tmp[i]
    inc pos

  entry.name[pos] = '\0'


proc reqPath(): cstring =
  cast[cstring](addr packet.data[0])


proc renderUptime(): U32 =
  clearOut()
  var pos = U32(0)
  appendStr(pos, cstring("ticks: "))
  appendU64(pos, sysTicks())
  appendChar(pos, '\n')
  pos


proc renderMeminfo(): U32 =
  clearOut()
  var pos = U32(0)

  if sysGetBitMap(addr bitmap) < 0:
    appendStr(pos, cstring("error\n"))
    return pos

  appendStr(pos, cstring("total: "))
  appendU64(pos, bitmap.total)
  appendStr(pos, cstring(" pages\n"))

  appendStr(pos, cstring("used : "))
  appendU64(pos, bitmap.used)
  appendStr(pos, cstring(" pages\n"))

  appendStr(pos, cstring("free : "))
  appendU64(pos, bitmap.free)
  appendStr(pos, cstring(" pages\n"))

  pos


proc renderCpuinfo(): U32 =
  clearOut()
  var pos = U32(0)

  if sysCpuInfo(addr cpuInfo) < 0:
    appendStr(pos, cstring("error\n"))
    return pos

  appendStr(pos, cstring("total_ticks: "))
  appendU64(pos, cpuInfo.totalTicks)
  appendChar(pos, '\n')

  appendStr(pos, cstring("idle_ticks : "))
  appendU64(pos, cpuInfo.idleTicks)
  appendChar(pos, '\n')

  appendStr(pos, cstring("busy_ticks : "))
  appendU64(pos, cpuInfo.busyTicks)
  appendChar(pos, '\n')

  appendStr(pos, cstring("usage      : "))
  appendU64(pos, U64(cpuInfo.usagePercent))
  appendStr(pos, cstring("%\n"))

  pos


proc userName(user: U32): cstring =
  if user == 0:
    cstring("kernel")
  else:
    cstring("user")


proc stateName(state: U32): cstring =
  if state == SysProcessRunnable:
    cstring("runnable")
  elif state == SysProcessRunning:
    cstring("running ")
  elif state == SysProcessSleeping:
    cstring("sleeping")
  elif state == SysProcessZombie:
    cstring("zombie  ")
  else:
    cstring("unused  ")


proc renderProcesses(): U32 =
  clearOut()
  var pos = U32(0)

  let count = sysPs(addr procInfos[0], U64(SysProcessMaxSlots), SysProcListAllSlots)
  if count < 0:
    appendStr(pos, cstring("error\n"))
    return pos

  appendStr(pos, cstring("pid\tppid\tstate\tuser\tcpu\tmem\texe\n"))

  var i = I32(0)
  while i < count:
    if procInfos[i].state != SysProcessUnused:
      appendI32(pos, procInfos[i].pid)
      appendChar(pos, '\t')
      appendI32(pos, procInfos[i].ppid)
      appendChar(pos, '\t')
      appendStr(pos, stateName(procInfos[i].state))
      appendChar(pos, '\t')
      appendStr(pos, userName(procInfos[i].isUser))
      appendChar(pos, '\t')
      appendPercent(pos, procInfos[i].cpuPercent)
      appendChar(pos, '\t')
      appendPages(pos, procInfos[i].memoryPages)
      appendChar(pos, '\t')
      appendStr(pos, cast[cstring](addr procInfos[i].exePath[0]))
      appendChar(pos, '\n')
    inc i
  
  pos


proc parseStatusPath(path: cstring, pid: var I32): bool =
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

  if not (path[i] == '/' and path[i + 1] == 's' and path[i + 2] == 't' and
      path[i + 3] == 'a' and path[i + 4] == 't' and path[i + 5] == 'u' and
      path[i + 6] == 's' and path[i + 7] == '\0'):
    return false

  pid = value
  true


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

      appendStr(pos, cstring("exe: "))
      appendStr(pos, cast[cstring](addr procInfos[i].exePath[0]))
      appendChar(pos, '\n')
      return pos
    inc i

  appendStr(pos, cstring("not found\n"))
  pos


proc ynString(state: U32): cstring =
  if state == 0:
    cstring("no")
  else:
    cstring("yes")


proc renderServices(): U32 =
  clearOut()
  var pos = U32(0)

  let count = sysServiceList(addr services[0], U64(8))
  if count < 0:
    appendStr(pos, cstring("error\n"))
    return pos

  appendStr(pos, cstring("name\tpid\tregistered\tavailable\n"))

  var i = I32(0)
  while i < count:
    appendStr(pos, cast[cstring](addr services[i].name[0]))
    appendChar(pos, '\t')
    appendI32(pos, services[i].pid)
    appendChar(pos, '\t')
    appendStr(pos, ynString(services[i].registered))
    appendChar(pos, '\t')
    appendStr(pos, ynString(services[i].available))
    appendChar(pos, '\n')
    inc i
  
  pos


proc renderTraps(): U32 =
  clearOut()
  var pos = U32(0)

  if sysTraps(addr traps) != 0:
    appendStr(pos, cstring("error\n"))
    return pos

  appendStr(pos, cstring"timer: ")
  appendU64(pos, traps.supervisorTimer)
  appendChar(pos, '\n')

  appendStr(pos, cstring"syscall: ")
  appendU64(pos, traps.environmentCallFromUMode)
  appendChar(pos, '\n')

  appendStr(pos, cstring"load_page_fault: ")
  appendU64(pos, traps.loadPageFault)
  appendChar(pos, '\n')

  appendStr(pos, cstring"store_page_fault: ")
  appendU64(pos, traps.storeAMOPageFault)
  appendChar(pos, '\n')

  appendStr(pos, cstring"inst_page_fault: ")
  appendU64(pos, traps.instructionPageFault)
  appendChar(pos, '\n')

  pos


proc procLsEntryLimit(): U32 =
  var capacity = packet.arg0
  if capacity > U64(SysIpcMessageMax):
    capacity = U64(SysIpcMessageMax)

  U32(capacity div U64(sizeof(DirEntry)))


proc renderLsProcRoot(): I32 =
  clearResponseData()

  let maxEntries = procLsEntryLimit()
  var count = U32(0)
  let entries = cast[ptr UncheckedArray[DirEntry]](addr response.data[0])

  template add(name: cstring, typ: U32) =
    if count < maxEntries:
      writeDirEntry(addr entries[count], name, typ)
      inc count

  var staticIndex = 0
  while staticIndex < ProcFsEntryCount:
    add(procEntries[staticIndex], DirEntryTypeFile)
    inc staticIndex

  let procCount = sysPs(addr procInfos[0], U64(SysProcessMaxSlots), SysProcListAllSlots)
  if procCount < 0:
    return -1

  var i = I32(0)
  while i < procCount:
    if procInfos[i].state != SysProcessUnused and count < maxEntries:
      writePidDirEntry(addr entries[count], procInfos[i].pid)
      inc count
    inc i

  response.len = count * U32(sizeof(DirEntry))
  I32(count)


proc renderLsProcPid(pid: I32): I32 =
  if not processExists(pid):
    return -1

  clearResponseData()
  if procLsEntryLimit() == U32(0):
    response.len = 0
    return 0

  let entries = cast[ptr UncheckedArray[DirEntry]](addr response.data[0])
  writeDirEntry(addr entries[0], cstring"status", DirEntryTypeFile)
  response.len = U32(sizeof(DirEntry))
  1


proc renderLsProc(path: cstring): I32 =
  if streq(path, cstring("/proc")) or streq(path, cstring("/proc/")):
    return renderLsProcRoot()

  var pid = I32(0)
  if parseProcPidPath(path, pid):
    return renderLsProcPid(pid)

  -1


proc renderRead(path: cstring): U32 =
  var pid = I32(0)
  if parseStatusPath(path, pid):
    return renderStatus(pid)

  if streq(path, cstring"/proc/uptime"):
    return renderUptime()

  if streq(path, cstring"/proc/meminfo"):
    return renderMeminfo()

  if streq(path, cstring"/proc/cpuinfo"):
    return renderCpuinfo()

  if streq(path, cstring"/proc/processes"):
    return renderProcesses()

  if streq(path, cstring"/proc/services"):
    return renderServices()

  if streq(path, cstring"/proc/traps"):
    return renderTraps()

  clearOut()
  U32(0)


proc copyOutToResponse(size: U32) =
  response.len = size

  var i = U32(0)
  while i < size and i < SysIpcMessageMax:
    response.data[i] = outBuf[i]
    inc i


proc handlePacket() =
  response = SysIpcPacket()
  response.op =
    if packet.op == SysIpcOpProcFsLsRequest:
      SysIpcOpProcFsLsResponse
    else:
      SysIpcOpProcFsReadResponse
  response.arg0 = U64(-1'i64)

  var size = U32(0)
  if packet.op == SysIpcOpProcFsLsRequest:
    let count = renderLsProc(reqPath())
    if count >= 0:
      response.arg0 = U64(count)
  
  elif packet.op == SysIpcOpProcFsReadRequest:
    size = renderRead(reqPath())
    if size > U32(0):
      response.arg0 = U64(size)
  
  if response.arg0 != U64(-1'i64) and packet.op == SysIpcOpProcFsReadRequest:
    copyOutToResponse(size)
  
  discard sysIpcSendPacket(packet.senderPid, addr response)


proc user_start*(arg: cstring) {.exportc, cdecl, noreturn.} =
  discard arg

  if not waitUntilServiceRegistered(SysServiceKindProcFs):
    write("[procfsd] service registration timeout\n")
    sysExit(1)
  
  notifyServiceReady(SysServiceKindProcFs)

  while true:
    if sysIpcReceivePacket(addr packet) < 0:
      write("[procfsd] receive failed\n")
      sysExit(1)
    handlePacket()
