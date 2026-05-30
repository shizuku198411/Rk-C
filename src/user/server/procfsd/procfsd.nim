## Implements the procfs userspace server with ORC-owned rendering workspaces.
{.warning[UnusedImport]: off.}

import ../../lib/runtime/orc_osalloc
import ../../lib/core/io
import ../../lib/core/syscall
import ../../lib/core/strutils
import ../../lib/core/passwd
import ../../lib/core/group
import ../../lib/core/userdb
import ../../../lib/mem
import ../../../lib/syscall_caps
import ../lib/service_ready


const
  ProcFsChunkMax = U32(SysIpcMessageMax)
  ProcFsBufSize = U32(SysKmsgMax)
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
  renderedText: string = ""
  procInfos: seq[SysProcessInfo] = @[]
  services: seq[SysServiceInfo] = @[]
  traps: SysTrapCount
  bitmap: SysBitmapInfo
  cpuInfo: SysCpuInfo
  fsInfos: seq[SysFsInfoEntry] = @[]
  fdInfos: seq[SysFdInfo] = @[]
  measuringOutput = false
  renderOffset = U32(0)
  renderCapacity = U32(SysIpcMessageMax)
  renderLen = U32(0)


## Allocates stable ORC-owned workspaces used while generating procfs replies.
proc initManagedStorage(): bool =
  procInfos = newSeq[SysProcessInfo](int(SysProcessMaxSlots))
  services = newSeq[SysServiceInfo](8)
  fsInfos = newSeq[SysFsInfoEntry](int(SysFsInfoMaxEntries))
  fdInfos = newSeq[SysFdInfo](int(SysFdMax))

  procInfos.len == int(SysProcessMaxSlots) and
    services.len == 8 and
    fsInfos.len == int(SysFsInfoMaxEntries) and
    fdInfos.len == int(SysFdMax)


## Includes formats procfs response text and virtual directory entries.
include ./internal/formatting


## Returns the pathname contained in the current procfs IPC request packet.
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


## Renders a virtual procfs regular file identified by its absolute path.
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


## Measures one procfs regular file without producing IPC payload bytes.
proc measureRead(path: cstring): U32 =
  measuringOutput = true
  renderOffset = U32(0)
  renderCapacity = U32(0)
  renderLen = U32(0)

  let size = renderRead(path)

  measuringOutput = false
  clearOut()
  size


## Configures fixed-size chunk output for the current procfs read request.
proc prepareChunkOutput() =
  measuringOutput = false
  renderOffset =
    if packet.arg1 > U64(high(U32)):
      high(U32)
    else:
      U32(packet.arg1)
  renderCapacity =
    if packet.arg0 > U64(ProcFsChunkMax):
      ProcFsChunkMax
    else:
      U32(packet.arg0)
  renderLen = U32(0)


## Copies the rendered procfs chunk into the fixed IPC response buffer.
proc copyRenderedChunkToResponse() =
  response.len = renderLen
  if renderLen == U32(0):
    return

  discard copyMem(addr response.data[0], cast[pointer](renderedText.cstring), U64(renderLen))


## Dispatches one procfs request and replies with fixed-format IPC payload data.
proc handlePacket() =
  response = SysIpcPacket()
  if packet.op == SysIpcOpProcFsLsRequest:
    response.op = SysIpcOpProcFsLsResponse
  elif packet.op == SysIpcOpProcFsSizeRequest:
    response.op = SysIpcOpProcFsSizeResponse
  else:
    response.op = SysIpcOpProcFsReadResponse
  response.arg0 = U64(-1'i64)

  var size = U32(0)
  if packet.op == SysIpcOpProcFsLsRequest:
    let count = renderLsProc(reqPath())
    if count >= 0:
      response.arg0 = U64(count)
  
  elif packet.op == SysIpcOpProcFsSizeRequest:
    size = measureRead(reqPath())
    response.arg0 = U64(size)

  elif packet.op == SysIpcOpProcFsReadRequest:
    prepareChunkOutput()
    size = renderRead(reqPath())
    response.arg0 = U64(size)
  
  if response.arg0 != U64(-1'i64) and packet.op == SysIpcOpProcFsReadRequest:
    copyRenderedChunkToResponse()
  
  discard sysIpcSendPacket(packet.senderPid, addr response)
  renderedText = ""


## Initializes the server and processes procfs IPC requests indefinitely.
proc user_start*(arg: cstring) {.exportc, cdecl, noreturn.} =
  discard arg

  if not initManagedStorage():
    write("[procfsd] managed workspace allocation failed\n")
    sysExit(1)

  if not waitUntilServiceRegistered(SysServiceKindProcFs):
    write("[procfsd] service registration timeout\n")
    sysExit(1)
  
  notifyServiceReady(SysServiceKindProcFs)

  while true:
    if sysIpcReceivePacket(addr packet) < 0:
      write("[procfsd] receive failed\n")
      sysExit(1)
    handlePacket()
