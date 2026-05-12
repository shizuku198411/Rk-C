import ../../lib/types
import ../dev/console
import ../fs/dirent
import ../fs/tmpfs
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
  AppfsMaxEntries = 32

  FsTypeFile = U32(1)
  FsTypeDir = U32(2)
  FsTypeMount = U32(3)
  VfsMaxMounts = 4

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
    path: cstring
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
  fsReady: bool
  mounts: array[VfsMaxMounts, VfsMount]
  mountCount: int
  appfsEntries: array[AppfsMaxEntries, AppfsEntry]
  appfsEntryCount: U32
  appfsReady: bool


proc fsWriteFile*(path: cstring, data: pointer, size: U64): int


proc cstrlen(s: cstring): int =
  if s == nil:
    return 0

  var n = 0
  while s[n] != '\0':
    inc n
  n


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
  mounts[idx].path = path
  mounts[idx].pathLen = cstrlen(path)
  mounts[idx].backend = backend
  mounts[idx].used = true
  inc mountCount


proc findMount(path: cstring): int =
  var best = -1
  var i = 0
  while i < mountCount:
    if mounts[i].used and pathMatchesMount(path, mounts[i].path, mounts[i].pathLen):
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


proc pathEq(a, b: cstring): bool =
  if a == nil or b == nil:
    return false
  var i = 0
  while a[i] == b[i]:
    if a[i] == '\0':
      return true
    inc i
  false


proc isBinRoot(path: cstring): bool =
  pathEq(path, "/bin") or pathEq(path, "/bin/")


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


proc appfsNameEq(entry: AppfsEntry, name: cstring): bool =
  var i = 0
  while i < FsNameMax:
    if entry.name[i] != name[i]:
      return false
    if entry.name[i] == '\0':
      return true
    inc i
  name[FsNameMax] == '\0'


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
    if appfsNameEq(appfsEntries[i], name):
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


proc copyName(dst: var array[FsNameMax, char], src: cstring) =
  var i = 0
  while i < FsNameMax - 1 and src[i] != '\0':
    dst[i] = src[i]
    inc i
  while i < FsNameMax:
    dst[i] = '\0'
    inc i


proc nameEq(node: FsNode, name: cstring): bool =
  var i = 0
  while i < FsNameMax:
    if node.name[i] != name[i]:
      return false
    if node.name[i] == '\0':
      return true
    inc i
  name[FsNameMax] == '\0'


proc findChild(parent: int, name: cstring): int =
  var i = 0
  while i < FsMaxNodes:
    if superBlock.nodes[i].used != 0 and
        superBlock.nodes[i].parent == U32(parent) and
        nameEq(superBlock.nodes[i], name):
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
      copyName(superBlock.nodes[i].name, name)
      inc superBlock.count
      return i
    inc i
  -1


proc readComponent(path: cstring, pos: var int, name: var array[FsNameMax, char]): bool =
  while path[pos] == '/':
    inc pos
  if path[pos] == '\0':
    return false

  var i = 0
  var tooLong = false

  while path[pos] != '\0' and path[pos] != '/':
    if i < FsNameMax - 1:
      name[i] = path[pos]
      inc i
    else:
      tooLong = true
    inc pos
  
  if tooLong:
    name[0] = '\0'
    return false
  
  while i < FsNameMax:
    name[i] = '\0'
    inc i
  
  true


proc resolvePath(path: cstring): int =
  if path == nil or path[0] == '\0':
    return -1
  if path[0] == '/' and path[1] == '\0':
    return 0

  var pos = 0
  var current = 0
  var name: array[FsNameMax, char]
  while readComponent(path, pos, name):
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
  while readComponent(path, pos, name):
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


proc formatFs() =
  superBlock = FsSuper()
  superBlock.magic = FsMagic
  superBlock.count = 1
  superBlock.nodes[0].used = 1
  superBlock.nodes[0].typ = FsTypeDir
  superBlock.nodes[0].parent = 0
  copyName(superBlock.nodes[0].name, "/")

  discard allocNode(0, "tmp", FsTypeMount)
  discard allocNode(0, "bin", FsTypeDir)

  if writeSuper() < 0:
    panic("fs format failed")


proc ensureRootDir(name: cstring, typ: U32) =
  let before = superBlock.count
  discard allocNode(0, name, typ)
  if superBlock.count != before:
    discard writeSuper()


proc fsInit*() =
  blockServiceInit()
  
  if readSuper() < 0:
    panic("fs super read failed")

  if superBlock.magic != FsMagic:
    printBootMsg("  formatting disk\n")
    formatFs()
  else:
    printBootMsg("  disk fs mounted\n")

  ensureRootDir("tmp", FsTypeMount)
  ensureRootDir("bin", FsTypeDir)
  ensureRootDir("etc", FsTypeDir)

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
    if entryIndex >= U64(appfsEntryCount):
      return 0
    fillAppfsEntry(int(entryIndex), outEntry)
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

  var seen = U64(0)
  var i = 0
  while i < FsMaxNodes:
    if superBlock.nodes[i].used != 0 and superBlock.nodes[i].parent == U32(dir) and i != dir:
      if seen == entryIndex:
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

  if resolveAppfsPath(path) >= 0:
    return false

  let idx = resolvePath(path)
  if idx < 0:
    return false

  superBlock.nodes[idx].typ == FsTypeDir or superBlock.nodes[idx].typ == FsTypeMount


proc fsMkdir*(path: cstring): int =
  if not fsReady:
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
  if not fsReady:
    return -1
  if data == nil and size > 0:
    return -1
  if size > FsFileBlocks * BlockSize:
    return -1

  let mountIdx = findMount(path)
  if mountIdx >= 0 and mounts[mountIdx].backend == vfsTmpfs:
    return tmpfsWriteBytes(mountLocalPath(path, mounts[mountIdx].pathLen), data, size)

  var idx = resolvePath(path)
  if idx < 0:
    var leaf: array[FsNameMax, char]
    let parent = resolveParent(path, leaf)
    if parent < 0 or superBlock.nodes[parent].typ != FsTypeDir:
      return -1
    idx = allocNode(parent, cast[cstring](addr leaf[0]), FsTypeFile)

  if idx < 0 or superBlock.nodes[idx].typ != FsTypeFile:
    return -1

  superBlock.nodes[idx].size = U32(size)

  if writeFileBytes(superBlock.nodes[idx], data, size) < 0:
    return -1
  writeSuper()


proc fsUnlink*(path: cstring): int =
  if not fsReady:
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
  if isBinRoot(path):
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
