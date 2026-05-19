import ../../lib/core/io
import ../../lib/core/syscall
import ../../lib/core/strutils
import ../../../lib/syscall_caps
import ../lib/service_ready


const
  ProcFsBufSize = U32(SysIpcMessageMax)
  ProcFsEntryCount = 8
  ProcFsPageSize = U64(4096)
  ProcFsTickMillis = U64(20)


let procEntries = [
  cstring("uptime"),
  cstring("meminfo"),
  cstring("cpuinfo"),
  cstring("processes"),
  cstring("services"),
  cstring("traps"),
  cstring("kmsg"),
  cstring("fsinfo"),
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
  fsInfos: array[SysFsInfoMaxEntries, SysFsInfoEntry]


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


proc appendKb(pos: var U32, blocks, blockSize: U64) =
  let bytes = blocks * blockSize
  appendU64(pos, (bytes + U64(1023)) div U64(1024))


proc appendTwoDigits(pos: var U32, value: U64) =
  appendChar(pos, char(ord('0') + int((value div U64(10)) mod U64(10))))
  appendChar(pos, char(ord('0') + int(value mod U64(10))))


proc appendDuration(pos: var U32, ticks: U64) =
  let ticksPerSecond = U64(1000) div ProcFsTickMillis
  let totalSeconds = ticks div ticksPerSecond
  let hours = totalSeconds div U64(3600)
  let minutes = (totalSeconds div U64(60)) mod U64(60)
  let seconds = totalSeconds mod U64(60)

  appendTwoDigits(pos, hours)
  appendChar(pos, ':')
  appendTwoDigits(pos, minutes)
  appendChar(pos, ':')
  appendTwoDigits(pos, seconds)


proc appendHex64(pos: var U32, value: U64) =
  appendStr(pos, cstring("0x"))

  var shift = 60
  var started = false
  while shift >= 0:
    let nibble = int((value shr U64(shift)) and U64(0xf))
    if nibble != 0 or started or shift == 0:
      started = true
      if nibble < 10:
        appendChar(pos, char(ord('0') + nibble))
      else:
        appendChar(pos, char(ord('a') + nibble - 10))
    shift -= 4


proc appendRkxMapLine(pos: var U32, start, size: U64, perms, name: cstring) =
  if size == 0:
    return

  appendHex64(pos, start)
  appendChar(pos, '-')
  appendHex64(pos, start + size)
  appendChar(pos, ' ')
  appendStr(pos, perms)
  appendChar(pos, ' ')
  appendStr(pos, name)
  appendChar(pos, '\n')


proc appendCapName(pos: var U32, mask: U32, cap: U32, name: cstring, first: var bool) =
  if (mask and cap) == 0:
    return

  if not first:
    appendChar(pos, ',')
  appendStr(pos, name)
  first = false


proc appendCapNames(pos: var U32, mask: U32) =
  if mask == SysCapNone:
    appendStr(pos, cstring("none"))
    return

  var first = true
  appendCapName(pos, mask, SysCapServiceManager, cstring(SysCapServiceManagerName), first)
  appendCapName(pos, mask, SysCapRawFs, cstring(SysCapRawFsName), first)
  appendCapName(pos, mask, SysCapRawBlock, cstring(SysCapRawBlockName), first)
  appendCapName(pos, mask, SysCapRawNet, cstring(SysCapRawNetName), first)
  appendCapName(pos, mask, SysCapProcessList, cstring(SysCapProcessListName), first)
  appendCapName(pos, mask, SysCapProcessKill, cstring(SysCapProcessKillName), first)
  appendCapName(pos, mask, SysCapTrace, cstring(SysCapTraceName), first)
  appendCapName(pos, mask, SysCapShutdown, cstring(SysCapShutdownName), first)

  let unknown = mask and (not SysCapAllKnown)
  if unknown != SysCapNone:
    if not first:
      appendChar(pos, ' ')
    appendStr(pos, cstring("unknown:"))
    appendHex64(pos, U64(unknown))


proc appendCapMaskLine(pos: var U32, label: cstring, mask: U32) =
  appendStr(pos, label)
  appendStr(pos, cstring(": "))
  appendHex64(pos, U64(mask))
  appendStr(pos, cstring(" ("))
  appendCapNames(pos, mask)
  appendStr(pos, cstring(")\n"))


proc appendSignalName(pos: var U32, mask, bit: U32, name: cstring, first: var bool) =
  if (mask and bit) == 0:
    return

  if not first:
    appendChar(pos, ',')
  appendStr(pos, name)
  first = false


proc signalMask(signal: U32): U32 =
  U32(1'u32 shl signal)


proc appendSignalNames(pos: var U32, mask: U32) =
  if mask == U32(0):
    appendStr(pos, cstring("none"))
    return

  var first = true
  appendSignalName(pos, mask, signalMask(SysSignalTerminate), cstring("terminate"), first)
  appendSignalName(pos, mask, signalMask(SysSignalInterrupt), cstring("interrupt"), first)
  appendSignalName(pos, mask, signalMask(SysSignalChildExited), cstring("child_exited"), first)
  appendSignalName(pos, mask, signalMask(SysSignalServiceStopped), cstring("service_stopped"), first)


proc appendSignalMaskLine(pos: var U32, label: cstring, mask: U32) =
  appendStr(pos, label)
  appendStr(pos, cstring(": "))
  appendHex64(pos, U64(mask))
  appendStr(pos, cstring(" ("))
  appendSignalNames(pos, mask)
  appendStr(pos, cstring(")\n"))


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
  let ticks = sysTicks()

  appendStr(pos, cstring("uptime: "))
  appendDuration(pos, ticks)
  appendChar(pos, '\n')

  appendStr(pos, cstring("ticks: "))
  appendU64(pos, ticks)
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

  appendStr(pos, cstring("window_ticks: "))
  appendU64(pos, cpuInfo.windowTicks)
  appendChar(pos, '\n')

  appendStr(pos, cstring("idle_ticks  : "))
  appendU64(pos, cpuInfo.idleTicks)
  appendChar(pos, '\n')

  appendStr(pos, cstring("busy_ticks  : "))
  appendU64(pos, cpuInfo.busyTicks)
  appendChar(pos, '\n')

  appendStr(pos, cstring("usage       : "))
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


proc renderKmsg(): U32 =
  clearOut()
  let capacity = U64(ProcFsBufSize - U32(1))
  let n = sysKmsg(addr outBuf[0], capacity)
  if n < 0:
    var pos = U32(0)
    appendStr(pos, cstring("error\n"))
    return pos

  if U32(n) < ProcFsBufSize:
    outBuf[U32(n)] = '\0'

  U32(n)


proc renderFsinfo(): U32 =
  clearOut()
  var pos = U32(0)

  let count = sysFsInfo(addr fsInfos[0], U64(SysFsInfoMaxEntries))
  if count < 0:
    appendStr(pos, cstring("error\n"))
    return pos

  appendStr(pos, cstring("Filesystem\tType\t1K-blocks\tUsed\tAvail\tFiles\tIUsed\tIFree\tRO\tMounted on\n"))

  var i = U32(0)
  while i < U32(count):
    appendStr(pos, cast[cstring](addr fsInfos[i].name[0]))
    appendStr(pos, "\t\t")
    appendStr(pos, cast[cstring](addr fsInfos[i].fsType[0]))
    appendChar(pos, '\t')
    appendKb(pos, fsInfos[i].totalBlocks, fsInfos[i].blockSize)
    appendStr(pos, "\t\t")
    appendKb(pos, fsInfos[i].usedBlocks, fsInfos[i].blockSize)
    appendChar(pos, '\t')
    appendKb(pos, fsInfos[i].freeBlocks, fsInfos[i].blockSize)
    appendChar(pos, '\t')
    appendU64(pos, fsInfos[i].totalFiles)
    appendChar(pos, '\t')
    appendU64(pos, fsInfos[i].usedFiles)
    appendChar(pos, '\t')
    appendU64(pos, fsInfos[i].freeFiles)
    appendChar(pos, '\t')
    appendStr(pos, ynString(fsInfos[i].readonly))
    appendChar(pos, '\t')
    appendStr(pos, cast[cstring](addr fsInfos[i].mount[0]))
    appendChar(pos, '\n')
    inc i

  pos


proc procLsEntryLimit(): U32 =
  var capacity = packet.arg0
  if capacity > U64(SysIpcMessageMax):
    capacity = U64(SysIpcMessageMax)

  U32(capacity div U64(sizeof(DirEntry)))


proc procLsOffset(): U32 =
  U32(packet.arg1)


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

  response.len = count * U32(sizeof(DirEntry))
  I32(count)


proc renderLsProc(path: cstring): I32 =
  if cstringEq(path, cstring("/proc")) or cstringEq(path, cstring("/proc/")):
    return renderLsProcRoot()

  var pid = I32(0)
  if parseProcPidPath(path, pid):
    return renderLsProcPid(pid)

  -1


proc renderRead(path: cstring): U32 =
  var pid = I32(0)
  if parseStatusPath(path, pid):
    return renderStatus(pid)

  if parseRkxMapPath(path, pid):
    return renderRkxMap(pid)

  if cstringEq(path, cstring"/proc/uptime"):
    return renderUptime()

  if cstringEq(path, cstring"/proc/meminfo"):
    return renderMeminfo()

  if cstringEq(path, cstring"/proc/cpuinfo"):
    return renderCpuinfo()

  if cstringEq(path, cstring"/proc/processes"):
    return renderProcesses()

  if cstringEq(path, cstring"/proc/services"):
    return renderServices()

  if cstringEq(path, cstring"/proc/traps"):
    return renderTraps()

  if cstringEq(path, cstring"/proc/kmsg"):
    return renderKmsg()

  if cstringEq(path, cstring"/proc/fsinfo"):
    return renderFsinfo()

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
