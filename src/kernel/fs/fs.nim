import ../../lib/fixed_string
import ../../lib/mem
import ../../lib/syscall_types
import ../../lib/types
import ../dev/console
import ../fs/dirent
import ../fs/tmpfs
import ../lib/path
import ../syscall/blk/block_service_ops

const
  FsMagic = U32(0x4e465332) # NFS2
  FsMaxNodes* = 32
  FsNameMax* = 16
  FsMetaBlocks = U64(4)
  FsFileBlocks = U64(8)
  FsDataStartBlock = U64(8)
  AppfsMagic = U32(0x41504653) # APFS
  AppfsStartBlock = U64(4096)
  AppfsMaxEntries = 64

  FsTypeFile = U32(1)
  FsTypeDir = U32(2)
  FsTypeMount = U32(3)
  VfsMaxMounts = 4
  DevEntryCount = 4

type
  AppfsEntry {.packed.} = object
    name: array[FsNameMax, char]
    dataOff: U32
    size: U32

  AppfsHeader {.packed.} = object
    magic: U32
    count: U32

  VfsBackend = enum
    vfsRootfs,
    vfsTmpfs

  VfsMount = object
    used: bool
    path: array[FsNameMax, char]
    pathLen: int
    backend: VfsBackend

  FsNode {.packed.} = object
    used: U32
    typ: U32
    parent: U32
    size: U32
    startBlock: U32
    name: array[FsNameMax, char]

  FsSuper {.packed.} = object
    magic: U32
    count: U32
    nodes: array[FsMaxNodes, FsNode]

var
  superBlock: FsSuper
  blockBuf: array[512, U8]
  fsWriteBuf: array[SysFsDataMax, U8]
  fsReady: bool
  mounts: array[VfsMaxMounts, VfsMount]
  mountCount: int
  appfsEntries: array[AppfsMaxEntries, AppfsEntry]
  appfsEntryCount: U32
  appfsReady: bool

let devEntryNames = [
  cstring("stdin"),
  cstring("stdout"),
  cstring("stderr"),
  cstring("console"),
]


proc fsWriteFile*(path: cstring, data: pointer, size: U64): int
proc fsWriteFileWithFlags*(path: cstring, data: pointer, size: U64, flags: U32): int
proc fsRename*(oldPath, newPath: cstring): int


proc copyInfoString(dst: var array[SysFsInfoNameMax, char], src: cstring) =
  var i = U32(0)
  while i + U32(1) < SysFsInfoNameMax and src[i] != '\0':
    dst[i] = src[i]
    inc i
  while i < SysFsInfoNameMax:
    dst[i] = '\0'
    inc i


proc pathMatchesMount(path: cstring, mountPath: cstring, mountLen: int): bool =
  if path == nil or mountPath == nil or mountLen <= 0:
    return false

  var i = 0
  while i < mountLen:
    if path[i] != mountPath[i]:
      return false
    inc i
  path[mountLen] == '\0' or path[mountLen] == '/'


proc mountLocalPath(path: cstring, mountLen: int): cstring =
  if path[mountLen] == '\0':
    return "/"
  cast[cstring](unsafeAddr path[mountLen])


proc vfsMount(path: cstring, backend: VfsBackend) =
  if path == nil or path[0] == '\0':
    panic("invalid vfs mount path")
  if mountCount >= VfsMaxMounts:
    panic("vfs mount table full")

  let idx = mountCount
  discard copyCString(mounts[idx].path, path)
  mounts[idx].pathLen = int(cstrlen(path))
  mounts[idx].backend = backend
  mounts[idx].used = true
  inc mountCount


proc findMount(path: cstring): int =
  var best = -1
  var i = 0
  while i < mountCount:
    if mounts[i].used and
        pathMatchesMount(path, cast[cstring](addr mounts[i].path[0]), mounts[i].pathLen):
      if best < 0 or mounts[i].pathLen > mounts[best].pathLen:
        best = i
    inc i
  best


proc clearMounts() =
  var i = 0
  while i < VfsMaxMounts:
    mounts[i] = VfsMount()
    inc i
  mountCount = 0


proc isBinRoot(path: cstring): bool =
  cstringEq(path, "/bin") or cstringEq(path, "/bin/")


proc isBinPath(path: cstring): bool =
  if path == nil:
    return false

  isBinRoot(path) or
    (path[0] == '/' and path[1] == 'b' and path[2] == 'i' and
      path[3] == 'n' and path[4] == '/')


proc isDevRoot(path: cstring): bool =
  cstringEq(path, "/dev") or cstringEq(path, "/dev/")


proc resolveDevPath(path: cstring): int =
  if path == nil or not (path[0] == '/' and path[1] == 'd' and path[2] == 'e' and
      path[3] == 'v' and path[4] == '/'):
    return -1

  let name = cast[cstring](unsafeAddr path[5])
  if name[0] == '\0':
    return -1

  var i = 0
  while i < DevEntryCount:
    if cstringEq(name, devEntryNames[i]):
      return i
    inc i

  -1


proc appfsReadBytes(absOff: U64, outBuf: pointer, n: U64): int =
  if outBuf == nil and n > 0:
    return -1

  let dst = cast[ptr UncheckedArray[U8]](outBuf)
  var done = U64(0)
  while done < n:
    let cur = absOff + done
    let blk = cur div BlockSize
    let inBlk = cur mod BlockSize
    if serviceBlockRead(blk, addr blockBuf[0]) < 0:
      return -1

    var chunk = BlockSize - inBlk
    if chunk > n - done:
      chunk = n - done

    var i = U64(0)
    while i < chunk:
      dst[done + i] = blockBuf[inBlk + i]
      inc i
    done += chunk
  0


proc appfsNameEq(entry: ptr AppfsEntry, name: cstring): bool =
  if entry == nil:
    return false

  fixedCStringEq(cast[ptr UncheckedArray[char]](addr entry.name[0]), FsNameMax, name)


proc resolveAppfsPath(path: cstring): int =
  if path == nil or not appfsReady:
    return -1
  if not (path[0] == '/' and path[1] == 'b' and path[2] == 'i' and
      path[3] == 'n' and path[4] == '/'):
    return -1

  let name = cast[cstring](unsafeAddr path[5])
  if name[0] == '\0':
    return -1

  var p = 0
  while name[p] != '\0':
    if name[p] == '/':
      return -1
    inc p

  var i = 0
  while i < int(appfsEntryCount):
    if appfsNameEq(addr appfsEntries[i], name):
      return i
    inc i
  -1


proc appfsLoad(): int =
  var hdr: AppfsHeader
  let base = AppfsStartBlock * BlockSize
  if appfsReadBytes(base, addr hdr, U64(sizeof(AppfsHeader))) < 0:
    return -1
  if hdr.magic != AppfsMagic or hdr.count > U32(AppfsMaxEntries):
    return -1

  appfsEntryCount = hdr.count
  if appfsEntryCount > 0:
    let tableBytes = U64(appfsEntryCount) * U64(sizeof(AppfsEntry))
    if appfsReadBytes(base + U64(sizeof(AppfsHeader)), addr appfsEntries[0], tableBytes) < 0:
      return -1

  appfsReady = true
  0


proc clearBlock() =
  var i = U64(0)
  while i < BlockSize:
    blockBuf[i] = 0
    inc i


proc findChild(parent: int, name: cstring): int =
  var i = 0
  while i < FsMaxNodes:
    if superBlock.nodes[i].used != 0 and
        superBlock.nodes[i].parent == U32(parent) and
        fixedCStringEq(
          cast[ptr UncheckedArray[char]](addr superBlock.nodes[i].name[0]),
          FsNameMax,
          name,
        ):
      return i
    inc i
  -1


proc hasChildren(idx: int): bool =
  var i = 0
  while i < FsMaxNodes:
    if superBlock.nodes[i].used != 0 and superBlock.nodes[i].parent == U32(idx) and i != idx:
      return true
    inc i
  false


proc writeSuper(): int =
  let src = cast[ptr UncheckedArray[U8]](addr superBlock)
  var copied = U64(0)
  var blk = U64(0)
  while blk < FsMetaBlocks:
    clearBlock()
    var i = U64(0)
    while i < BlockSize and copied < U64(sizeof(FsSuper)):
      blockBuf[i] = src[copied]
      inc i
      inc copied
    if serviceBlockWrite(blk, addr blockBuf[0]) < 0:
      return -1
    inc blk
  0


proc readSuper(): int =
  let dst = cast[ptr UncheckedArray[U8]](addr superBlock)
  var copied = U64(0)
  var blk = U64(0)
  while blk < FsMetaBlocks:
    if serviceBlockRead(blk, addr blockBuf[0]) < 0:
      return -1
    var i = U64(0)
    while i < BlockSize and copied < U64(sizeof(FsSuper)):
      dst[copied] = blockBuf[i]
      inc i
      inc copied
    inc blk
  0


proc allocNode(parent: int, name: cstring, typ: U32): int =
  let existing = findChild(parent, name)
  if existing >= 0:
    return existing

  var i = 1
  while i < FsMaxNodes:
    if superBlock.nodes[i].used == 0:
      superBlock.nodes[i].used = 1
      superBlock.nodes[i].typ = typ
      superBlock.nodes[i].parent = U32(parent)
      superBlock.nodes[i].size = 0
      superBlock.nodes[i].startBlock = U32(FsDataStartBlock + U64(i) * FsFileBlocks)
      discard copyCString(superBlock.nodes[i].name, name)
      inc superBlock.count
      return i
    inc i
  -1


proc resolvePath(path: cstring): int =
  if path == nil or path[0] == '\0':
    return -1
  if path[0] == '/' and path[1] == '\0':
    return 0

  var pos = 0
  var current = 0
  var name: array[FsNameMax, char]
  while readPathComponent(path, pos, name):
    let next = findChild(current, cast[cstring](addr name[0]))
    if next < 0:
      return -1
    current = next
  current


proc resolveParent(path: cstring, leaf: var array[FsNameMax, char]): int =
  if path == nil or path[0] == '\0':
    return -1

  var pos = 0
  var current = 0
  var name: array[FsNameMax, char]
  while readPathComponent(path, pos, name):
    if path[pos] == '\0':
      leaf = name
      return current
    let next = findChild(current, cast[cstring](addr name[0]))
    if next < 0 or superBlock.nodes[next].typ == FsTypeFile:
      return -1
    current = next
  -1


proc writeFileBytes(node: FsNode, data: pointer, size: U64): int =
  if data == nil and size > 0:
    return -1
  if size > FsFileBlocks * BlockSize:
    return -1

  let src = cast[ptr UncheckedArray[U8]](data)
  var written = U64(0)

  var blk = U64(0)
  while blk < FsFileBlocks:
    clearBlock()
    var i = U64(0)
    while i < BlockSize and written < size:
      blockBuf[i] = src[written]
      inc i
      inc written
    if serviceBlockWrite(U64(node.startBlock) + blk, addr blockBuf[0]) < 0:
      return -1
    inc blk
  0


proc readNodeBytes(node: FsNode, dst: pointer, capacity: U64): int =
  if dst == nil:
    return -1
  if U64(node.size) > capacity:
    return -1

  let outBuf = cast[ptr UncheckedArray[U8]](dst)
  var done = U64(0)
  while done < U64(node.size):
    let blockIndex = done div BlockSize
    let inBlock = done mod BlockSize
    if serviceBlockRead(U64(node.startBlock) + blockIndex, addr blockBuf[0]) < 0:
      return -1

    var chunk = BlockSize - inBlock
    if chunk > U64(node.size) - done:
      chunk = U64(node.size) - done

    var i = U64(0)
    while i < chunk:
      outBuf[done + i] = blockBuf[inBlock + i]
      inc i
    done += chunk

  int(node.size)


proc formatFs() =
  superBlock = FsSuper()
  superBlock.magic = FsMagic
  superBlock.count = 1
  superBlock.nodes[0].used = 1
  superBlock.nodes[0].typ = FsTypeDir
  superBlock.nodes[0].parent = 0
  discard copyCString(superBlock.nodes[0].name, "/")

  discard allocNode(0, "tmp", FsTypeMount)
  discard allocNode(0, "bin", FsTypeDir)

  if writeSuper() < 0:
    panic("fs format failed")


proc ensureRootDir(name: cstring, typ: U32): bool =
  let before = superBlock.count
  discard allocNode(0, name, typ)
  superBlock.count != before


proc ensureDir(parentIdx: int, name: cstring, typ: U32): bool =
  if parentIdx < 0 or superBlock.nodes[parentIdx].typ != FsTypeDir:
    return false
  if name == nil or name[0] == '\0':
    return false

  var i = 0
  while name[i] != '\0':
    if name[i] == '/':
      return false
    inc i

  let before = superBlock.count
  discard allocNode(parentIdx, name, typ)
  superBlock.count != before


proc fsInit*() =
  blockServiceInit()
  
  if readSuper() < 0:
    panic("fs super read failed")

  if superBlock.magic != FsMagic:
    printBootMsg("  formatting disk\n")
    formatFs()
  else:
    printBootMsg("  disk fs mounted\n")

  var fsChanged = false
  fsChanged = ensureRootDir("tmp", FsTypeMount) or fsChanged
  fsChanged = ensureRootDir("bin", FsTypeDir) or fsChanged
  fsChanged = ensureRootDir("etc", FsTypeDir) or fsChanged
  fsChanged = ensureRootDir("dev", FsTypeDir) or fsChanged
  fsChanged = ensureRootDir("var", FsTypeDir) or fsChanged

  let varIdx = resolvePath("/var")
  fsChanged = ensureDir(varIdx, "log", FsTypeDir) or fsChanged

  if fsChanged and writeSuper() < 0:
    panic("fs ensure dirs failed")

  if appfsLoad() < 0:
    panic("appfs load failed")
  printBootMsg("  mounted /bin entries = ")
  printUnsigned(U64(appfsEntryCount))
  putChar('\n')

  clearMounts()
  tmpfsInit()
  vfsMount("/tmp", vfsTmpfs)
  printBootMsg("  mounted tmpfs on /tmp\n")
  fsReady = true


proc rootfsUsedBlocks(): U64 =
  var blocks = U64(0)
  var i = 0
  while i < FsMaxNodes:
    if superBlock.nodes[i].used != 0 and superBlock.nodes[i].typ == FsTypeFile:
      blocks += FsFileBlocks
    inc i
  blocks


proc appfsUsedBytes(): U64 =
  if not appfsReady:
    return U64(0)

  var bytes = U64(sizeof(AppfsHeader)) + U64(appfsEntryCount) * U64(sizeof(AppfsEntry))
  var i = U32(0)
  while i < appfsEntryCount:
    let endOff = U64(appfsEntries[i].dataOff) + U64(appfsEntries[i].size)
    if endOff > bytes:
      bytes = endOff
    inc i
  bytes


proc setFsInfo(entry: ptr SysFsInfoEntry, name, fsType, mount: cstring,
               blockSize, totalBlocks, usedBlocks, totalFiles, usedFiles: U64,
               readonly: U32) =
  entry[] = SysFsInfoEntry()
  copyInfoString(entry.name, name)
  copyInfoString(entry.fsType, fsType)
  copyInfoString(entry.mount, mount)
  entry.blockSize = blockSize
  entry.totalBlocks = totalBlocks
  entry.usedBlocks = usedBlocks
  entry.freeBlocks =
    if usedBlocks > totalBlocks:
      U64(0)
    else:
      totalBlocks - usedBlocks
  entry.totalFiles = totalFiles
  entry.usedFiles = usedFiles
  entry.freeFiles =
    if usedFiles > totalFiles:
      U64(0)
    else:
      totalFiles - usedFiles
  entry.readonly = readonly


proc fsInfo*(outEntries: ptr SysFsInfoEntry, maxEntries: U64): I32 =
  if outEntries == nil or maxEntries == U64(0):
    return -1

  let entries = cast[ptr UncheckedArray[SysFsInfoEntry]](outEntries)
  var count = U64(0)

  if count < maxEntries:
    let totalBlocks = U64(FsMaxNodes) * FsFileBlocks
    setFsInfo(
      addr entries[count],
      cstring"rootfs",
      cstring"nfs2",
      cstring"/",
      BlockSize,
      totalBlocks,
      rootfsUsedBlocks(),
      U64(FsMaxNodes),
      U64(superBlock.count),
      U32(0),
    )
    inc count

  if count < maxEntries:
    let blocksPerNode = tmpfsMaxFileBytes() div BlockSize
    let totalBlocks = tmpfsMaxNodes() * blocksPerNode
    setFsInfo(
      addr entries[count],
      cstring"tmpfs",
      cstring"tmpfs",
      cstring"/tmp",
      BlockSize,
      totalBlocks,
      tmpfsUsedBlocks(BlockSize),
      tmpfsMaxNodes(),
      tmpfsUsedNodes(),
      U32(0),
    )
    inc count

  if count < maxEntries:
    let usedBytes = appfsUsedBytes()
    let usedBlocks = (usedBytes + BlockSize - U64(1)) div BlockSize
    setFsInfo(
      addr entries[count],
      cstring"appfs",
      cstring"appfs",
      cstring"/bin",
      BlockSize,
      usedBlocks,
      usedBlocks,
      U64(AppfsMaxEntries),
      U64(appfsEntryCount),
      U32(1),
    )
    inc count

  I32(count)


proc fillNodeEntry(idx: int, outEntry: ptr FsDirEntry) =
  outEntry.typ = superBlock.nodes[idx].typ
  outEntry.size = superBlock.nodes[idx].size

  var i = 0
  while i < FsDirEntryNameMax:
    outEntry.name[i] = superBlock.nodes[idx].name[i]
    inc i


proc fillAppfsEntry(idx: int, outEntry: ptr FsDirEntry) =
  outEntry.typ = FsDirEntryTypeFile
  outEntry.size = appfsEntries[idx].size

  var i = 0
  while i < FsDirEntryNameMax:
    outEntry.name[i] = appfsEntries[idx].name[i]
    inc i


proc fillDevEntry(idx: int, outEntry: ptr FsDirEntry) =
  outEntry.typ = FsDirEntryTypeFile
  outEntry.size = 0

  var i = 0
  let name = devEntryNames[idx]
  while i < FsDirEntryNameMax:
    if name[i] == '\0':
      break
    outEntry.name[i] = name[i]
    inc i

  while i < FsDirEntryNameMax:
    outEntry.name[i] = '\0'
    inc i


proc fillVirtualDirEntry(name: cstring, outEntry: ptr FsDirEntry) =
  outEntry.typ = FsDirEntryTypeDir
  outEntry.size = 0

  var i = 0
  while i < FsDirEntryNameMax:
    if name[i] == '\0':
      break
    outEntry.name[i] = name[i]
    inc i

  while i < FsDirEntryNameMax:
    outEntry.name[i] = '\0'
    inc i


proc fsReadDirEntry*(path: cstring, entryIndex: U64, outEntry: ptr FsDirEntry): int =
  if not fsReady:
    return -1

  let mountIdx = findMount(path)
  if mountIdx >= 0 and mounts[mountIdx].backend == vfsTmpfs:
    return tmpfsReadDirEntry(mountLocalPath(path, mounts[mountIdx].pathLen), entryIndex, outEntry)

  let appFileIdx = resolveAppfsPath(path)
  if appFileIdx >= 0:
    if entryIndex != 0:
      return 0
    fillAppfsEntry(appFileIdx, outEntry)
    return 1

  if isBinRoot(path):
    if not appfsReady:
      return -1
    var realEntryIndex = entryIndex
    if realEntryIndex == U64(0):
      fillVirtualDirEntry(".", outEntry)
      return 1
    if realEntryIndex == U64(1):
      fillVirtualDirEntry("..", outEntry)
      return 1
    realEntryIndex -= U64(2)
    if realEntryIndex >= U64(appfsEntryCount):
      return 0
    fillAppfsEntry(int(realEntryIndex), outEntry)
    return 1

  if isDevRoot(path):
    var realEntryIndex = entryIndex
    if realEntryIndex == U64(0):
      fillVirtualDirEntry(".", outEntry)
      return 1
    if realEntryIndex == U64(1):
      fillVirtualDirEntry("..", outEntry)
      return 1
    realEntryIndex -= U64(2)
    if realEntryIndex >= U64(DevEntryCount):
      return 0
    fillDevEntry(int(realEntryIndex), outEntry)
    return 1

  let devIdx = resolveDevPath(path)
  if devIdx >= 0:
    if entryIndex != 0:
      return 0
    fillDevEntry(devIdx, outEntry)
    return 1

  let dir = resolvePath(path)
  if dir < 0:
    return -1

  if superBlock.nodes[dir].typ == FsTypeFile:
    if entryIndex != 0:
      return 0
    fillNodeEntry(dir, outEntry)
    return 1

  if superBlock.nodes[dir].typ == FsTypeMount:
    return tmpfsReadDirEntry("/", entryIndex, outEntry)

  var realEntryIndex = entryIndex
  if realEntryIndex == U64(0):
    fillVirtualDirEntry(".", outEntry)
    return 1
  if realEntryIndex == U64(1):
    fillVirtualDirEntry("..", outEntry)
    return 1
  realEntryIndex -= U64(2)

  var seen = U64(0)
  var i = 0
  while i < FsMaxNodes:
    if superBlock.nodes[i].used != 0 and superBlock.nodes[i].parent == U32(dir) and i != dir:
      if seen == realEntryIndex:
        fillNodeEntry(i, outEntry)
        return 1
      inc seen
    inc i
  0


proc fsReadDirEntries*(path: cstring, outEntries: ptr FsDirEntry, maxEntries: U64): int =
  if outEntries == nil or maxEntries == 0:
    return -1

  let entries = cast[ptr UncheckedArray[FsDirEntry]](outEntries)
  var count = U64(0)
  while count < maxEntries:
    let readResult = fsReadDirEntry(path, count, addr entries[count])
    if readResult < 0:
      if count == 0:
        return -1
      return int(count)
    if readResult == 0:
      return int(count)
    inc count

  int(count)


proc fsIsDir*(path: cstring): bool =
  if not fsReady or path == nil or path[0] != '/':
    return false

  let mountIdx = findMount(path)
  if mountIdx >= 0 and mounts[mountIdx].backend == vfsTmpfs:
    return tmpfsIsDir(mountLocalPath(path, mounts[mountIdx].pathLen))

  if isBinRoot(path):
    return true

  if isDevRoot(path):
    return true

  if resolveAppfsPath(path) >= 0:
    return false

  if resolveDevPath(path) >= 0:
    return false

  let idx = resolvePath(path)
  if idx < 0:
    return false

  superBlock.nodes[idx].typ == FsTypeDir or superBlock.nodes[idx].typ == FsTypeMount


proc fsFileSize*(path: cstring): int =
  if not fsReady or path == nil:
    return -1

  let mountIdx = findMount(path)
  if mountIdx >= 0 and mounts[mountIdx].backend == vfsTmpfs:
    return tmpfsFileSize(mountLocalPath(path, mounts[mountIdx].pathLen))

  let appIdx = resolveAppfsPath(path)
  if appIdx >= 0:
    return int(appfsEntries[appIdx].size)

  let idx = resolvePath(path)
  if idx < 0 or superBlock.nodes[idx].typ != FsTypeFile:
    return -1

  int(superBlock.nodes[idx].size)


proc fsMkdir*(path: cstring): int =
  if not fsReady:
    return -1
  if isBinPath(path):
    return -1

  let mountIdx = findMount(path)
  if mountIdx >= 0 and mounts[mountIdx].backend == vfsTmpfs:
    return tmpfsMkdir(mountLocalPath(path, mounts[mountIdx].pathLen))

  var leaf: array[FsNameMax, char]
  let parent = resolveParent(path, leaf)
  if parent < 0 or superBlock.nodes[parent].typ == FsTypeFile:
    return -1
  if superBlock.nodes[parent].typ == FsTypeMount:
    return -1

  let idx = allocNode(parent, cast[cstring](addr leaf[0]), FsTypeDir)
  if idx < 0:
    return -1
  writeSuper()


proc fsWriteText*(path: cstring, data: cstring): int =
  var size = U64(0)
  while data[size] != '\0' and size < FsFileBlocks * BlockSize:
    inc size
  fsWriteFile(path, cast[pointer](data), size)


proc fsWriteFile*(path: cstring, data: pointer, size: U64): int =
  fsWriteFileWithFlags(path, data, size, SysFsWriteDefault)


proc fsWriteFileWithFlags*(path: cstring, data: pointer, size: U64, flags: U32): int =
  if not fsReady:
    return -1
  if isBinPath(path):
    return -1
  if data == nil and size > 0:
    return -1
  if size > FsFileBlocks * BlockSize:
    return -1
  if (flags and (not SysFsWriteKnownFlags)) != U32(0):
    return -1

  let mode = flags and (SysFsWriteOverwrite or SysFsWriteAppend)
  if mode == U32(0) or mode == (SysFsWriteOverwrite or SysFsWriteAppend):
    return -1

  let mountIdx = findMount(path)
  if mountIdx >= 0 and mounts[mountIdx].backend == vfsTmpfs:
    return tmpfsWriteBytesWithFlags(mountLocalPath(path, mounts[mountIdx].pathLen), data, size, flags)

  var idx = resolvePath(path)
  if idx < 0:
    if (flags and SysFsWriteCreate) == U32(0):
      return -1

    var leaf: array[FsNameMax, char]
    let parent = resolveParent(path, leaf)
    if parent < 0 or superBlock.nodes[parent].typ != FsTypeDir:
      return -1
    idx = allocNode(parent, cast[cstring](addr leaf[0]), FsTypeFile)

  if idx < 0 or superBlock.nodes[idx].typ != FsTypeFile:
    return -1

  let writeData =
    if (mode and SysFsWriteAppend) != U32(0):
      if readNodeBytes(superBlock.nodes[idx], addr fsWriteBuf[0], U64(SysFsDataMax)) < 0:
        return -1
      let currentSize = U64(superBlock.nodes[idx].size)
      if currentSize + size > FsFileBlocks * BlockSize:
        return -1
      if size > 0:
        discard copyMem(addr fsWriteBuf[currentSize], data, size)
      superBlock.nodes[idx].size = U32(currentSize + size)
      cast[pointer](addr fsWriteBuf[0])
    else:
      superBlock.nodes[idx].size = U32(size)
      data

  if writeFileBytes(superBlock.nodes[idx], writeData, U64(superBlock.nodes[idx].size)) < 0:
    return -1
  writeSuper()


proc fsUnlink*(path: cstring): int =
  if not fsReady:
    return -1
  if isBinPath(path):
    return -1

  let mountIdx = findMount(path)
  if mountIdx >= 0 and mounts[mountIdx].backend == vfsTmpfs:
    return tmpfsUnlink(mountLocalPath(path, mounts[mountIdx].pathLen))

  if resolveAppfsPath(path) >= 0:
    return -1

  let idx = resolvePath(path)
  if idx <= 0 or superBlock.nodes[idx].typ != FsTypeFile:
    return -1

  superBlock.nodes[idx] = FsNode()
  if superBlock.count > 0:
    dec superBlock.count
  writeSuper()


proc fsRmdir*(path: cstring): int =
  if not fsReady:
    return -1
  if isBinPath(path):
    return -1

  let mountIdx = findMount(path)
  if mountIdx >= 0 and mounts[mountIdx].backend == vfsTmpfs:
    return tmpfsRmdir(mountLocalPath(path, mounts[mountIdx].pathLen))

  let idx = resolvePath(path)
  if idx <= 0 or superBlock.nodes[idx].typ != FsTypeDir or hasChildren(idx):
    return -1

  superBlock.nodes[idx] = FsNode()
  if superBlock.count > 0:
    dec superBlock.count
  writeSuper()


proc isDescendant(idx, maybeParent: int): bool =
  var current = idx
  while current > 0:
    if current == maybeParent:
      return true
    current = int(superBlock.nodes[current].parent)
  false


proc fsRename*(oldPath, newPath: cstring): int =
  if not fsReady:
    return -1
  if oldPath == nil or newPath == nil:
    return -1
  if isBinPath(oldPath) or isBinPath(newPath):
    return -1

  let oldMountIdx = findMount(oldPath)
  let newMountIdx = findMount(newPath)
  if oldMountIdx >= 0 or newMountIdx >= 0:
    if oldMountIdx < 0 or newMountIdx < 0 or oldMountIdx != newMountIdx:
      return -1
    if mounts[oldMountIdx].backend == vfsTmpfs:
      return tmpfsRename(
        mountLocalPath(oldPath, mounts[oldMountIdx].pathLen),
        mountLocalPath(newPath, mounts[newMountIdx].pathLen),
      )
    return -1

  if resolveAppfsPath(oldPath) >= 0 or resolveAppfsPath(newPath) >= 0:
    return -1
  if resolveDevPath(oldPath) >= 0 or resolveDevPath(newPath) >= 0:
    return -1

  let src = resolvePath(oldPath)
  if src <= 0:
    return -1
  if resolvePath(newPath) >= 0:
    return -1

  var leaf: array[FsNameMax, char]
  let newParent = resolveParent(newPath, leaf)
  if newParent < 0 or superBlock.nodes[newParent].typ != FsTypeDir:
    return -1
  if superBlock.nodes[src].typ == FsTypeDir and isDescendant(newParent, src):
    return -1

  superBlock.nodes[src].parent = U32(newParent)
  discard copyCString(superBlock.nodes[src].name, cast[cstring](addr leaf[0]))
  writeSuper()


proc fsReadFile*(path: cstring, dst: pointer, capacity: U64): int =
  if not fsReady or path == nil or dst == nil:
    return -1

  let mountIdx = findMount(path)
  if mountIdx >= 0 and mounts[mountIdx].backend == vfsTmpfs:
    return tmpfsReadFile(mountLocalPath(path, mounts[mountIdx].pathLen), dst, capacity)

  let appIdx = resolveAppfsPath(path)
  if appIdx >= 0:
    let size = U64(appfsEntries[appIdx].size)
    if size > capacity:
      return -1
    let base = AppfsStartBlock * BlockSize + U64(appfsEntries[appIdx].dataOff)
    if appfsReadBytes(base, dst, size) < 0:
      return -1
    return int(size)

  let idx = resolvePath(path)
  if idx < 0 or superBlock.nodes[idx].typ != FsTypeFile:
    return -1
  let node = superBlock.nodes[idx]
  let size = U64(node.size)
  if size > capacity:
    return -1

  let outBuf = cast[ptr UncheckedArray[U8]](dst)
  var done = U64(0)
  var blk = U64(0)
  while done < size and blk < FsFileBlocks:
    if serviceBlockRead(U64(node.startBlock) + blk, addr blockBuf[0]) < 0:
      return -1
    var i = U64(0)
    while i < BlockSize and done < size:
      outBuf[done] = blockBuf[i]
      inc i
      inc done
    inc blk
  int(size)


proc fsReadFileRange*(path: cstring, dst: pointer, offset, capacity: U64): int =
  if not fsReady or path == nil or dst == nil:
    return -1
  if capacity == U64(0):
    return 0

  let mountIdx = findMount(path)
  if mountIdx >= 0 and mounts[mountIdx].backend == vfsTmpfs:
    return tmpfsReadRange(mountLocalPath(path, mounts[mountIdx].pathLen), dst, offset, capacity)

  let appIdx = resolveAppfsPath(path)
  if appIdx >= 0:
    let size = U64(appfsEntries[appIdx].size)
    if offset >= size:
      return 0

    var readLen = size - offset
    if readLen > capacity:
      readLen = capacity

    let base = AppfsStartBlock * BlockSize + U64(appfsEntries[appIdx].dataOff) + offset
    if appfsReadBytes(base, dst, readLen) < 0:
      return -1
    return int(readLen)

  let idx = resolvePath(path)
  if idx < 0 or superBlock.nodes[idx].typ != FsTypeFile:
    return -1

  let node = superBlock.nodes[idx]
  let size = U64(node.size)
  if offset >= size:
    return 0

  var readLen = size - offset
  if readLen > capacity:
    readLen = capacity

  let outBuf = cast[ptr UncheckedArray[U8]](dst)
  var done = U64(0)
  while done < readLen:
    let cur = offset + done
    let blk = cur div BlockSize
    let inBlk = cur mod BlockSize
    if blk >= FsFileBlocks:
      return -1
    if serviceBlockRead(U64(node.startBlock) + blk, addr blockBuf[0]) < 0:
      return -1

    var chunk = BlockSize - inBlk
    if chunk > readLen - done:
      chunk = readLen - done

    var i = U64(0)
    while i < chunk:
      outBuf[done + i] = blockBuf[inBlk + i]
      inc i
    done += chunk

  int(readLen)
