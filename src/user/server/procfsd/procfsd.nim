import ../../lib/core/io
import ../../lib/core/syscall
import ../../lib/core/strutils
import ../lib/service_ready


const
  ProcFsBufSize = U32(SysIpcMessageMax)
  ProcFsEntryCount = 5


let procEntries = [
  cstring("uptime"),
  cstring("meminfo"),
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


proc stateName(state: U32): cstring =
  if state == SysProcessRunnable:
    cstring("runnable")
  elif state == SysProcessRunning:
    cstring("running")
  elif state == SysProcessSleeping:
    cstring("sleeping")
  elif state == SysProcessZombie:
    cstring("zombie")
  else:
    cstring("unused")


proc renderProcesses(): U32 =
  clearOut()
  var pos = U32(0)

  let count = sysPs(addr procInfos[0], U64(SysProcessMaxSlots), SysProcListAllSlots)
  if count < 0:
    appendStr(pos, cstring("error\n"))
    return pos

  appendStr(pos, cstring("pid\tppid\tstate\tuser\texe\n"))

  var i = I32(0)
  while i < count:
    if procInfos[i].state != SysProcessUnused:
      appendI32(pos, procInfos[i].pid)
      appendChar(pos, '\t')
      appendI32(pos, procInfos[i].ppid)
      appendChar(pos, '\t')
      appendStr(pos, stateName(procInfos[i].state))
      appendChar(pos, '\t')
      appendU64(pos, U64(procInfos[i].isUser))
      appendChar(pos, '\t')
      appendStr(pos, cast[cstring](addr procInfos[i].exePath[0]))
      appendChar(pos, '\n')
    inc i
  
  pos


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
    appendU64(pos, U64(services[i].registered))
    appendChar(pos, '\t')
    appendU64(pos, U64(services[i].available))
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


proc renderLsProc(): U32 =
  clearOut()
  var pos = U32(0)

  var i = 0
  while i < ProcFsEntryCount:
    appendStr(pos, procEntries[i])
    appendChar(pos, '\n')
    inc i

  pos


proc renderRead(path: cstring): U32 =
  if streq(path, cstring"/proc/uptime"):
    return renderUptime()

  if streq(path, cstring"/proc/meminfo"):
    return renderMeminfo()

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
    if streq(reqPath(), cstring("/proc")) or streq(reqPath(), cstring("/proc/")):
      size = renderLsProc()
      response.arg0 = U64(size)
  
  elif packet.op == SysIpcOpProcFsReadRequest:
    size = renderRead(reqPath())
    if size > U32(0):
      response.arg0 = U64(size)
  
  if response.arg0 != U64(-1'i64):
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
