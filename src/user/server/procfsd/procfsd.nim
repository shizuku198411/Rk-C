import ../../lib/core/io
import ../../lib/core/syscall
import ../../lib/core/strutils
import ../../lib/core/passwd
import ../../lib/core/group
import ../../lib/core/userdb
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
  fdInfos: array[SysFdMax, SysFdInfo]


## Includes formats procfs response text and virtual directory entries.
include ./internal/formatting


proc reqPath(): cstring =
  cast[cstring](addr packet.data[0])


## Includes renders procfs host and process-list information files.
include ./internal/system_views


## Includes parses process paths and renders per-process procfs views.
include ./internal/process_views


## Includes renders service, trap, log, and filesystem status procfs views.
include ./internal/service_views


## Includes enumerates procfs root, process, and file-descriptor directories.
include ./internal/directory_views


## Includes renders open file-descriptor information for procfs.
include ./internal/fd_views


proc renderRead(path: cstring): U32 =
  var pid = I32(0)
  var fd = I32(0)

  if parseFdEntryPath(path, pid, fd):
    return renderFdInfo(pid, fd)

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
