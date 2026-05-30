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
import ../../../lib/service_catalog
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
  readCacheText: string = ""
  readCachePath: array[SysIpcMessageMax, char]
  readCacheValid = false
  readCacheSize = U32(0)
  sizeCachePath: array[SysIpcMessageMax, char]
  sizeCacheValid = false
  sizeCacheSize = U32(0)
  sizeCacheTick = U64(0)
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
  services = newSeq[SysServiceInfo](SysServiceRegistryCount)
  fsInfos = newSeq[SysFsInfoEntry](int(SysFsInfoMaxEntries))
  fdInfos = newSeq[SysFdInfo](int(SysFdMax))

  procInfos.len == int(SysProcessMaxSlots) and
    services.len == SysServiceRegistryCount and
    fsInfos.len == int(SysFsInfoMaxEntries) and
    fdInfos.len == int(SysFdMax)


## Includes formats procfs response text and virtual directory entries.
include ./internal/formatting


## Returns the pathname contained in the current procfs IPC request packet.
proc reqPath(): cstring =
  cast[cstring](addr packet.data[0])


## Copies a procfs request path into a cache key buffer.
proc copyCachePath(dst: var array[SysIpcMessageMax, char], path: cstring) =
  var i = U32(0)
  while i + U32(1) < U32(SysIpcMessageMax) and path[i] != '\0':
    dst[i] = path[i]
    inc i

  dst[i] = '\0'


## Returns whether a cache key buffer matches a procfs request path.
proc cachePathMatches(src: var array[SysIpcMessageMax, char], path: cstring): bool =
  cstringEq(cast[cstring](addr src[0]), path)


## Drops the cached chunk-read rendering state.
proc invalidateReadCache() =
  readCacheText = ""
  readCacheValid = false
  readCacheSize = U32(0)


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
  if readCacheValid and cachePathMatches(readCachePath, path):
    return readCacheSize

  let now = sysTicks()
  if sizeCacheValid and sizeCacheTick == now and cachePathMatches(sizeCachePath, path):
    return sizeCacheSize

  measuringOutput = true
  renderOffset = U32(0)
  renderCapacity = U32(0)
  renderLen = U32(0)

  let size = renderRead(path)

  measuringOutput = false
  clearOut()
  sizeCacheSize = size
  sizeCacheTick = now
  copyCachePath(sizeCachePath, path)
  sizeCacheValid = true
  size


## Renders one procfs file into the read cache for chunked transfer.
proc renderReadCache(path: cstring): bool =
  if readCacheValid and cachePathMatches(readCachePath, path):
    return true

  invalidateReadCache()

  measuringOutput = false
  renderOffset = U32(0)
  renderCapacity = ProcFsBufSize - U32(1)
  renderLen = U32(0)

  let size = renderRead(path)
  readCacheText = renderedText
  readCacheSize = size
  copyCachePath(readCachePath, path)
  readCacheValid = true

  sizeCacheSize = size
  sizeCacheTick = sysTicks()
  copyCachePath(sizeCachePath, path)
  sizeCacheValid = true

  renderedText = ""
  renderLen = U32(0)
  true


## Copies a requested read-cache range into the fixed IPC response buffer.
proc copyReadCacheRangeToResponse(offset, capacity: U64) =
  response.arg0 = U64(readCacheSize)
  response.len = U32(0)

  if offset >= U64(readCacheSize):
    invalidateReadCache()
    return

  var copySize = U64(readCacheSize) - offset
  if copySize > capacity:
    copySize = capacity
  if copySize > U64(ProcFsChunkMax):
    copySize = U64(ProcFsChunkMax)

  let cachedLen = U64(readCacheText.len)
  if offset >= cachedLen:
    invalidateReadCache()
    return
  if copySize > cachedLen - offset:
    copySize = cachedLen - offset

  if copySize > U64(0):
    discard copyMem(addr response.data[0], addr readCacheText[int(offset)], copySize)
    response.len = U32(copySize)

  if offset + copySize >= U64(readCacheSize):
    invalidateReadCache()


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
    if renderReadCache(reqPath()):
      copyReadCacheRangeToResponse(packet.arg1, packet.arg0)
  
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
