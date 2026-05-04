import ../../kernel/console
import ../../kernel/fs/blockdev
import ../../kernel/fs/tmpfs
import ../../lib/types

type
  U32 = uint32

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

proc cstrlen(s: cstring): int =
  var n = 0
  while s[n] != '\0':
    inc n
  n

proc pathMatchesMount(path: cstring, mountPath: cstring, mountLen: int): bool =
  if path == nil:
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
  if mountCount >= VfsMaxMounts:
    panic("vfs mount table full")
  mounts[mountCount].used = true
  mounts[mountCount].path = path
  mounts[mountCount].pathLen = cstrlen(path)
  mounts[mountCount].backend = backend
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
    if blockRead(blk, addr blockBuf[0]) < 0:
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
    if blockWrite(blk, addr blockBuf[0]) < 0:
      return -1
    inc blk
  0

proc readSuper(): int =
  let dst = cast[ptr UncheckedArray[U8]](addr superBlock)
  var copied = U64(0)
  var blk = U64(0)
  while blk < FsMetaBlocks:
    if blockRead(blk, addr blockBuf[0]) < 0:
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
  while path[pos] != '\0' and path[pos] != '/':
    if i < FsNameMax - 1:
      name[i] = path[pos]
      inc i
    inc pos
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

proc writeFileData(node: FsNode, data: cstring): int =
  var written = U64(0)
  let remaining = U64(cstrlen(data))

  var blk = U64(0)
  while blk < FsFileBlocks:
    clearBlock()
    var i = U64(0)
    while i < BlockSize and written < remaining:
      blockBuf[i] = U8(ord(data[written]))
      inc i
      inc written
    if blockWrite(U64(node.startBlock) + blk, addr blockBuf[0]) < 0:
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

  let readmeIdx = allocNode(0, "README", FsTypeFile)
  let readme = cstring("hello from disk fs\ntry: ls /, ls /tmp, cat /README, mkdir /home\n")
  superBlock.nodes[readmeIdx].size = U32(cstrlen(readme))
  discard writeFileData(superBlock.nodes[readmeIdx], readme)

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
  blockdevInit()
  
  if readSuper() < 0:
    panic("fs super read failed")

  if superBlock.magic != FsMagic:
    printBootMsg("formatting disk\n")
    formatFs()
  else:
    printBootMsg("disk fs mounted\n")

  ensureRootDir("tmp", FsTypeMount)
  ensureRootDir("bin", FsTypeDir)

  if appfsLoad() < 0:
    panic("appfs load failed")
  printBootMsg("mounted /bin entries = ")
  printUnsigned(U64(appfsEntryCount))
  putChar('\n')

  mountCount = 0
  tmpfsInit()
  vfsMount("/tmp", vfsTmpfs)
  printBootMsg("mounted tmpfs on /tmp\n")
  fsReady = true

proc printNodeName(idx: int) =
  print(cast[cstring](addr superBlock.nodes[idx].name[0]))
  if superBlock.nodes[idx].typ == FsTypeDir or superBlock.nodes[idx].typ == FsTypeMount:
    putChar('/')

proc fsList*(path: cstring = "/") =
  if not fsReady:
    println("fs not ready")
    return

  let mountIdx = findMount(path)
  if mountIdx >= 0 and mounts[mountIdx].backend == vfsTmpfs:
    discard tmpfsList(mountLocalPath(path, mounts[mountIdx].pathLen))
    return

  if isBinRoot(path):
    if not appfsReady:
      println("appfs not ready")
      return
    var appIdx = 0
    while appIdx < int(appfsEntryCount):
      print(cast[cstring](addr appfsEntries[appIdx].name[0]))
      putChar(' ')
      printUnsigned(U64(appfsEntries[appIdx].size))
      println(" bytes")
      inc appIdx
    return

  let dir = resolvePath(path)
  if dir < 0:
    println("not found")
    return
  if superBlock.nodes[dir].typ == FsTypeFile:
    printNodeName(dir)
    putChar(' ')
    printUnsigned(U64(superBlock.nodes[dir].size))
    println(" bytes")
    return

  if superBlock.nodes[dir].typ == FsTypeMount:
    discard tmpfsList("/")
    return

  var i = 0
  while i < FsMaxNodes:
    if superBlock.nodes[i].used != 0 and superBlock.nodes[i].parent == U32(dir) and i != dir:
      printNodeName(i)
      if superBlock.nodes[i].typ == FsTypeFile:
        putChar(' ')
        printUnsigned(U64(superBlock.nodes[i].size))
        print(" bytes")
      elif superBlock.nodes[i].typ == FsTypeMount:
        print(" mount")
      putChar('\n')
    inc i

proc fsCat*(path: cstring): int =
  if not fsReady:
    return -1
  let mountIdx = findMount(path)
  if mountIdx >= 0 and mounts[mountIdx].backend == vfsTmpfs:
    return tmpfsCat(mountLocalPath(path, mounts[mountIdx].pathLen))
  if resolveAppfsPath(path) >= 0:
    return -1

  let idx = resolvePath(path)
  if idx < 0 or superBlock.nodes[idx].typ != FsTypeFile:
    return -1

  let node = superBlock.nodes[idx]
  var done = U64(0)
  var blk = U64(0)
  while done < U64(node.size) and blk < FsFileBlocks:
    if blockRead(U64(node.startBlock) + blk, addr blockBuf[0]) < 0:
      return -1
    var i = U64(0)
    while i < BlockSize and done < U64(node.size):
      putChar(char(blockBuf[i]))
      inc i
      inc done
    inc blk
  if done == 0 or blockBuf[(done - 1) mod BlockSize] != U8(ord('\n')):
    putChar('\n')
  0

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
  if not fsReady:
    return -1
  let mountIdx = findMount(path)
  if mountIdx >= 0 and mounts[mountIdx].backend == vfsTmpfs:
    return tmpfsWriteText(mountLocalPath(path, mounts[mountIdx].pathLen), data)

  var idx = resolvePath(path)
  if idx < 0:
    var leaf: array[FsNameMax, char]
    let parent = resolveParent(path, leaf)
    if parent < 0 or superBlock.nodes[parent].typ != FsTypeDir:
      return -1
    idx = allocNode(parent, cast[cstring](addr leaf[0]), FsTypeFile)

  if idx < 0 or superBlock.nodes[idx].typ != FsTypeFile:
    return -1

  var size = U32(0)
  while data[size] != '\0' and U64(size) < FsFileBlocks * BlockSize:
    inc size
  superBlock.nodes[idx].size = size

  if writeFileData(superBlock.nodes[idx], data) < 0:
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
  if not fsReady or dst == nil:
    return -1

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
    if blockRead(U64(node.startBlock) + blk, addr blockBuf[0]) < 0:
      return -1
    var i = U64(0)
    while i < BlockSize and done < size:
      outBuf[done] = blockBuf[i]
      inc i
      inc done
    inc blk
  int(size)
