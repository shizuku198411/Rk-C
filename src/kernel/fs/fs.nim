## Implements the root filesystem, appfs, devfs views, VFS dispatch, and permissions.
import ../../lib/fixed_string
import ../../lib/fs_permissions
import ../../lib/mem
import ../../lib/syscall_types
import ../../lib/types
import ../../lib/user_ids
import ../dev/console
import ../fs/dirent
import ../fs/tmpfs
import ../lib/path
import ../syscall/blk/block_service_ops

const
  FsMagic = U32(0x4e465332) # NFS2
  FsMaxNodes* = 40
  FsNameMax* = 16
  FsMetaBlocks = U64(4)
  FsMetaBytes = 2048
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
  OsReleaseContent = cstring"""NAME="Rk-C"
VERSION="0.1.1"
GITHUB_URL="https://github.com/shizuku198411/Rk-C"
"""

type
  AppfsEntry {.packed.} = object
    name: array[FsNameMax, char]
    dataOff: U32
    size: U32

  AppfsHeader {.packed.} = object
    magic: U32
    count: U32

  FsOldNode {.packed.} = object
    used: U32
    typ: U32
    parent: U32
    size: U32
    startBlock: U32
    name: array[FsNameMax, char]

  FsOldSuper {.packed.} = object
    magic: U32
    count: U32
    nodes: array[FsMaxNodes, FsOldNode]

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
    uid: U32
    gid: U32
    mode: U32

  FsSuper {.packed.} = object
    magic: U32
    count: U32
    nodes: array[FsMaxNodes, FsNode]

var
  superBlock: FsSuper
  superRawBuf: array[FsMetaBytes, U8]
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


## Implements the fs write file kernel helper.
proc fsWriteFile*(path: cstring, data: pointer, size: U64): int
## Implements the fs write file with flags kernel helper.
proc fsWriteFileWithFlags*(path: cstring, data: pointer, size: U64, flags: U32): int
## Implements the fs rename kernel helper.
proc fsRename*(oldPath, newPath: cstring): int
## Implements the fs chmod kernel helper.
proc fsChmod*(path: cstring, mode: U32): int
## Implements the fs chown kernel helper.
proc fsChown*(path: cstring, uid, gid: U32): int
## Ensures a child node exists below an existing directory.
proc ensureDir(parentIdx: int, name: cstring, typ: U32): bool


## Implements the default node mode kernel helper.
proc defaultNodeMode(parent: int, name: cstring, typ: U32): U32 =
  if typ == FsTypeFile:
    return FsModeFileDefault
  if typ == FsTypeMount and parent == 0 and cstringEq(name, "tmp"):
    return FsModeStickyPublicDir
  if typ == FsTypeDir and parent == 0 and cstringEq(name, "bin"):
    return FsModeReadonlyDir

  FsModeDirDefault


## Initializes node metadata.
proc initNodeMetadata(node: ptr FsNode, parent: int, name: cstring, typ: U32) =
  if node == nil:
    return

  node.uid = RootUid
  node.gid = RootGid
  node.mode = defaultNodeMode(parent, name, typ)


## Implements the ensure node metadata kernel helper.
proc ensureNodeMetadata(idx: int): bool =
  if idx < 0 or idx >= FsMaxNodes:
    return false
  if superBlock.nodes[idx].used == 0:
    return false
  if superBlock.nodes[idx].mode != FsModeNone:
    return false

  initNodeMetadata(
    addr superBlock.nodes[idx],
    int(superBlock.nodes[idx].parent),
    cast[cstring](addr superBlock.nodes[idx].name[0]),
    superBlock.nodes[idx].typ,
  )
  true


## Implements the ensure all node metadata kernel helper.
proc ensureAllNodeMetadata(): bool =
  var changed = false
  var i = 0
  while i < FsMaxNodes:
    changed = ensureNodeMetadata(i) or changed
    inc i
  changed


## Checks whether read node is allowed.
proc canReadNode(uid, gid: U32, idx: int): bool =
  idx >= 0 and idx < FsMaxNodes and superBlock.nodes[idx].used != U32(0) and
    fsModeAllowsRead(superBlock.nodes[idx].uid, superBlock.nodes[idx].gid,
      superBlock.nodes[idx].mode, uid, gid)


## Checks whether write node is allowed.
proc canWriteNode(uid, gid: U32, idx: int): bool =
  idx >= 0 and idx < FsMaxNodes and superBlock.nodes[idx].used != U32(0) and
    fsModeAllowsWrite(superBlock.nodes[idx].uid, superBlock.nodes[idx].gid,
      superBlock.nodes[idx].mode, uid, gid)


## Checks whether execute node is allowed.
proc canExecuteNode(uid, gid: U32, idx: int): bool =
  idx >= 0 and idx < FsMaxNodes and superBlock.nodes[idx].used != U32(0) and
    fsModeAllowsExecute(superBlock.nodes[idx].uid, superBlock.nodes[idx].gid,
      superBlock.nodes[idx].mode, uid, gid)


## Checks whether search node is allowed.
proc canSearchNode(uid, gid: U32, idx: int): bool =
  idx >= 0 and idx < FsMaxNodes and superBlock.nodes[idx].used != U32(0) and
    (superBlock.nodes[idx].typ == FsTypeDir or superBlock.nodes[idx].typ == FsTypeMount) and
    canExecuteNode(uid, gid, idx)


## Copies info string.
proc copyInfoString(dst: var array[SysFsInfoNameMax, char], src: cstring) =
  var i = U32(0)
  while i + U32(1) < SysFsInfoNameMax and src[i] != '\0':
    dst[i] = src[i]
    inc i
  while i < SysFsInfoNameMax:
    dst[i] = '\0'
    inc i


## Implements the path matches mount kernel helper.
proc pathMatchesMount(path: cstring, mountPath: cstring, mountLen: int): bool =
  if path == nil or mountPath == nil or mountLen <= 0:
    return false

  var i = 0
  while i < mountLen:
    if path[i] != mountPath[i]:
      return false
    inc i
  path[mountLen] == '\0' or path[mountLen] == '/'


## Implements the mount local path kernel helper.
proc mountLocalPath(path: cstring, mountLen: int): cstring =
  if path[mountLen] == '\0':
    return "/"
  cast[cstring](unsafeAddr path[mountLen])


## Implements the vfs mount kernel helper.
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


## Finds mount.
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


## Clears mounts.
proc clearMounts() =
  var i = 0
  while i < VfsMaxMounts:
    mounts[i] = VfsMount()
    inc i
  mountCount = 0


## Returns whether bin root is true.
proc isBinRoot(path: cstring): bool =
  cstringEq(path, "/bin") or cstringEq(path, "/bin/")


## Returns whether bin path is true.
proc isBinPath(path: cstring): bool =
  if path == nil:
    return false

  isBinRoot(path) or
    (path[0] == '/' and path[1] == 'b' and path[2] == 'i' and
      path[3] == 'n' and path[4] == '/')


## Returns whether dev root is true.
proc isDevRoot(path: cstring): bool =
  cstringEq(path, "/dev") or cstringEq(path, "/dev/")


## Returns whether proc root is true.
proc isProcRoot(path: cstring): bool =
  cstringEq(path, "/proc") or cstringEq(path, "/proc/")


## Returns whether proc path is true.
proc isProcPath(path: cstring): bool =
  if path == nil:
    return false

  isProcRoot(path) or
    (path[0] == '/' and path[1] == 'p' and path[2] == 'r' and
      path[3] == 'o' and path[4] == 'c' and path[5] == '/')


## Resolves dev path.
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


## Implements the appfs read bytes kernel helper.
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


## Implements the appfs name eq kernel helper.
proc appfsNameEq(entry: ptr AppfsEntry, name: cstring): bool =
  if entry == nil:
    return false

  fixedCStringEq(cast[ptr UncheckedArray[char]](addr entry.name[0]), FsNameMax, name)


## Resolves appfs path.
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


## Implements the appfs load kernel helper.
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


## Clears block.
proc clearBlock() =
  var i = U64(0)
  while i < BlockSize:
    blockBuf[i] = 0
    inc i


## Finds child.
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


## Returns whether children is present.
proc hasChildren(idx: int): bool =
  var i = 0
  while i < FsMaxNodes:
    if superBlock.nodes[i].used != 0 and superBlock.nodes[i].parent == U32(idx) and i != idx:
      return true
    inc i
  false


## Writes super.
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


## Reads super.
proc readSuper(): int =
  var copied = U64(0)
  var blk = U64(0)
  while blk < FsMetaBlocks:
    if serviceBlockRead(blk, addr blockBuf[0]) < 0:
      return -1
    var i = U64(0)
    while i < BlockSize and copied < U64(FsMetaBytes):
      superRawBuf[copied] = blockBuf[i]
      inc i
      inc copied
    inc blk

  discard copyMem(addr superBlock, addr superRawBuf[0], U64(sizeof(FsSuper)))
  if superBlock.magic != FsMagic:
    return 0

  if superBlock.nodes[0].used != U32(0) and
      superBlock.nodes[0].typ == FsTypeDir and
      superBlock.nodes[0].mode != FsModeNone:
    return 0

  var oldSuper: FsOldSuper
  discard copyMem(addr oldSuper, addr superRawBuf[0], U64(sizeof(FsOldSuper)))
  superBlock = FsSuper()
  superBlock.magic = oldSuper.magic

  var usedCount = U32(0)
  var j = 0
  while j < FsMaxNodes:
    if oldSuper.nodes[j].used != U32(0):
      superBlock.nodes[j].used = oldSuper.nodes[j].used
      superBlock.nodes[j].typ = oldSuper.nodes[j].typ
      superBlock.nodes[j].parent = oldSuper.nodes[j].parent
      superBlock.nodes[j].size = oldSuper.nodes[j].size
      superBlock.nodes[j].startBlock = oldSuper.nodes[j].startBlock
      discard copyMem(addr superBlock.nodes[j].name[0], addr oldSuper.nodes[j].name[0], U64(FsNameMax))
      initNodeMetadata(
        addr superBlock.nodes[j],
        int(superBlock.nodes[j].parent),
        cast[cstring](addr superBlock.nodes[j].name[0]),
        superBlock.nodes[j].typ,
      )
      inc usedCount
    inc j

  superBlock.count = usedCount
  0


## Allocates node.
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
      initNodeMetadata(addr superBlock.nodes[i], parent, name, typ)
      inc superBlock.count
      return i
    inc i
  -1


## Resolves path.
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


## Resolves path with search.
proc resolvePathWithSearch(uid, gid: U32, path: cstring): int =
  if path == nil or path[0] == '\0':
    return -1
  if path[0] == '/' and path[1] == '\0':
    return 0

  var pos = 0
  var current = 0
  var name: array[FsNameMax, char]
  while readPathComponent(path, pos, name):
    if not canSearchNode(uid, gid, current):
      return -1

    let next = findChild(current, cast[cstring](addr name[0]))
    if next < 0:
      return -1
    current = next
  current


## Resolves parent.
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


## Resolves parent with search.
proc resolveParentWithSearch(uid, gid: U32, path: cstring, leaf: var array[FsNameMax, char]): int =
  if path == nil or path[0] == '\0':
    return -1

  var pos = 0
  var current = 0
  var name: array[FsNameMax, char]
  while readPathComponent(path, pos, name):
    if not canSearchNode(uid, gid, current):
      return -1

    if path[pos] == '\0':
      leaf = name
      return current
    let next = findChild(current, cast[cstring](addr name[0]))
    if next < 0 or superBlock.nodes[next].typ == FsTypeFile:
      return -1
    current = next
  -1


## Writes file bytes.
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


## Reads node bytes.
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


## Implements the format fs kernel helper.
proc formatFs() =
  superBlock = FsSuper()
  superBlock.magic = FsMagic
  superBlock.count = 1
  superBlock.nodes[0].used = 1
  superBlock.nodes[0].typ = FsTypeDir
  superBlock.nodes[0].parent = 0
  discard copyCString(superBlock.nodes[0].name, "/")
  initNodeMetadata(addr superBlock.nodes[0], 0, "/", FsTypeDir)

  discard allocNode(0, "tmp", FsTypeMount)
  discard allocNode(0, "bin", FsTypeDir)

  if writeSuper() < 0:
    panic("fs format failed")


## Implements the ensure root dir kernel helper.
proc ensureRootDir(name: cstring, typ: U32): bool =
  let before = superBlock.count
  discard allocNode(0, name, typ)
  superBlock.count != before


## Implements the ensure root dir owned kernel helper.
proc ensureRootDirOwned(name: cstring, typ, uid, gid, mode: U32): bool =
  var changed = ensureRootDir(name, typ)
  let idx = findChild(0, name)
  if idx < 0:
    return changed

  if superBlock.nodes[idx].uid != uid:
    superBlock.nodes[idx].uid = uid
    changed = true
  if superBlock.nodes[idx].gid != gid:
    superBlock.nodes[idx].gid = gid
    changed = true
  if superBlock.nodes[idx].mode != mode:
    superBlock.nodes[idx].mode = mode
    changed = true

  changed


## Ensures a child directory exists with the requested owner and mode.
proc ensureChildDirOwned(parentIdx: int, name: cstring, uid, gid, mode: U32): bool =
  var changed = ensureDir(parentIdx, name, FsTypeDir)
  let idx = findChild(parentIdx, name)
  if idx < 0:
    return changed

  if superBlock.nodes[idx].uid != uid:
    superBlock.nodes[idx].uid = uid
    changed = true
  if superBlock.nodes[idx].gid != gid:
    superBlock.nodes[idx].gid = gid
    changed = true
  if superBlock.nodes[idx].mode != mode:
    superBlock.nodes[idx].mode = mode
    changed = true

  changed


## Implements the ensure dir kernel helper.
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


## Implements the cstring data size kernel helper.
proc cstringDataSize(data: cstring): U64 =
  var size = U64(0)
  while data[size] != '\0':
    inc size

  size


## Implements the ensure file content kernel helper.
proc ensureFileContent(parentIdx: int, name, data: cstring, uid, gid, mode: U32): bool =
  if parentIdx < 0 or superBlock.nodes[parentIdx].typ != FsTypeDir:
    return false

  let before = superBlock.count
  let idx = allocNode(parentIdx, name, FsTypeFile)
  if idx < 0:
    return false
  if superBlock.nodes[idx].typ != FsTypeFile:
    return false

  var changed = superBlock.count != before
  let size = cstringDataSize(data)

  if superBlock.nodes[idx].uid != uid:
    superBlock.nodes[idx].uid = uid
    changed = true
  if superBlock.nodes[idx].gid != gid:
    superBlock.nodes[idx].gid = gid
    changed = true
  if superBlock.nodes[idx].mode != mode:
    superBlock.nodes[idx].mode = mode
    changed = true
  if superBlock.nodes[idx].size != U32(size):
    superBlock.nodes[idx].size = U32(size)
    changed = true

  if writeFileBytes(superBlock.nodes[idx], cast[pointer](data), size) < 0:
    panic("failed to write ensured file")

  true


## Implements the fs init kernel helper.
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
  fsChanged = ensureAllNodeMetadata() or fsChanged
  fsChanged = ensureRootDir("tmp", FsTypeMount) or fsChanged
  fsChanged = ensureRootDir("bin", FsTypeDir) or fsChanged
  fsChanged = ensureRootDir("etc", FsTypeDir) or fsChanged
  fsChanged = ensureRootDir("dev", FsTypeDir) or fsChanged
  fsChanged = ensureRootDir("var", FsTypeDir) or fsChanged
  fsChanged = ensureRootDirOwned(
    "home",
    FsTypeDir,
    RootUid,
    RootGid,
    FsModeDirDefault,
  ) or fsChanged

  let homeIdx = resolvePath("/home")
  fsChanged = ensureChildDirOwned(
    homeIdx,
    "rkc",
    UserUid,
    UserGid,
    FsModeDirDefault,
  ) or fsChanged

  let varIdx = resolvePath("/var")
  fsChanged = ensureDir(varIdx, "log", FsTypeDir) or fsChanged
  let etcIdx = resolvePath("/etc")
  fsChanged = ensureFileContent(
    etcIdx,
    "os-release",
    OsReleaseContent,
    RootUid,
    RootGid,
    FsModeFileDefault,
  ) or fsChanged

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


## Implements the rootfs used blocks kernel helper.
proc rootfsUsedBlocks(): U64 =
  var blocks = U64(0)
  var i = 0
  while i < FsMaxNodes:
    if superBlock.nodes[i].used != 0 and superBlock.nodes[i].typ == FsTypeFile:
      blocks += FsFileBlocks
    inc i
  blocks


## Implements the appfs used bytes kernel helper.
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


## Sets fs info.
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


## Implements the fs info kernel helper.
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


## Implements the mount point allows search kernel helper.
proc mountPointAllowsSearch(uid, gid: U32, mountIdx: int): bool =
  if mountIdx < 0 or mountIdx >= mountCount:
    return false

  let mountPath = cast[cstring](addr mounts[mountIdx].path[0])
  let idx = resolvePathWithSearch(uid, gid, mountPath)
  canSearchNode(uid, gid, idx)


## Implements the appfs root idx with search kernel helper.
proc appfsRootIdxWithSearch(uid, gid: U32): int =
  resolvePathWithSearch(uid, gid, cstring"/bin")


## Implements the appfs root allows read kernel helper.
proc appfsRootAllowsRead(uid, gid: U32): bool =
  let idx = appfsRootIdxWithSearch(uid, gid)
  canReadNode(uid, gid, idx)


## Implements the appfs root allows search kernel helper.
proc appfsRootAllowsSearch(uid, gid: U32): bool =
  let idx = appfsRootIdxWithSearch(uid, gid)
  canSearchNode(uid, gid, idx)


## Implements the appfs file allows read kernel helper.
proc appfsFileAllowsRead(uid, gid: U32): bool =
  fsModeAllowsRead(RootUid, RootGid, FsModeReadonlyFile, uid, gid)


## Implements the appfs file allows execute kernel helper.
proc appfsFileAllowsExecute(uid, gid: U32): bool =
  fsModeAllowsExecute(RootUid, RootGid, FsModeReadonlyFile, uid, gid)


## Implements the dev file allows read kernel helper.
proc devFileAllowsRead(uid, gid: U32): bool =
  fsModeAllowsRead(RootUid, RootGid, FsModeDeviceFile, uid, gid)


## Implements the dev file allows write kernel helper.
proc devFileAllowsWrite(uid, gid: U32): bool =
  fsModeAllowsWrite(RootUid, RootGid, FsModeDeviceFile, uid, gid)


## Implements the fs can read path kernel helper.
proc fsCanReadPath*(uid, gid: U32, path: cstring): bool =
  if not fsReady or path == nil:
    return false

  let mountIdx = findMount(path)
  if mountIdx >= 0 and mounts[mountIdx].backend == vfsTmpfs:
    return mountPointAllowsSearch(uid, gid, mountIdx) and
      tmpfsCanRead(uid, gid, mountLocalPath(path, mounts[mountIdx].pathLen))

  if isBinRoot(path):
    return appfsRootAllowsRead(uid, gid)

  if resolveAppfsPath(path) >= 0:
    return appfsRootAllowsSearch(uid, gid) and appfsFileAllowsRead(uid, gid)

  if isProcPath(path):
    return true

  if isDevRoot(path):
    let idx = resolvePathWithSearch(uid, gid, path)
    return canReadNode(uid, gid, idx)

  if resolveDevPath(path) >= 0:
    return devFileAllowsRead(uid, gid)

  let idx = resolvePathWithSearch(uid, gid, path)
  canReadNode(uid, gid, idx)


## Implements the fs can write path kernel helper.
proc fsCanWritePath*(uid, gid: U32, path: cstring): bool =
  if not fsReady or path == nil:
    return false

  let mountIdx = findMount(path)
  if mountIdx >= 0 and mounts[mountIdx].backend == vfsTmpfs:
    return mountPointAllowsSearch(uid, gid, mountIdx) and
      tmpfsCanWrite(uid, gid, mountLocalPath(path, mounts[mountIdx].pathLen))

  if isBinPath(path) or resolveAppfsPath(path) >= 0:
    return false

  if isProcPath(path):
    return false

  if resolveDevPath(path) >= 0:
    return devFileAllowsWrite(uid, gid)

  let idx = resolvePathWithSearch(uid, gid, path)
  canWriteNode(uid, gid, idx)


## Implements the fs can execute path kernel helper.
proc fsCanExecutePath*(uid, gid: U32, path: cstring): bool =
  if not fsReady or path == nil:
    return false

  let mountIdx = findMount(path)
  if mountIdx >= 0 and mounts[mountIdx].backend == vfsTmpfs:
    return mountPointAllowsSearch(uid, gid, mountIdx) and
      tmpfsCanExecute(uid, gid, mountLocalPath(path, mounts[mountIdx].pathLen))

  if isBinRoot(path):
    return appfsRootAllowsSearch(uid, gid)

  if resolveAppfsPath(path) >= 0:
    return appfsRootAllowsSearch(uid, gid) and appfsFileAllowsExecute(uid, gid)

  if isProcPath(path):
    return false

  if resolveDevPath(path) >= 0:
    return false

  let idx = resolvePathWithSearch(uid, gid, path)
  canExecuteNode(uid, gid, idx)


## Implements the fs execute status kernel helper.
proc fsExecuteStatus*(uid, gid: U32, path: cstring): I32 =
  if not fsReady or path == nil:
    return SysErrInval

  let mountIdx = findMount(path)
  if mountIdx >= 0 and mounts[mountIdx].backend == vfsTmpfs:
    if not mountPointAllowsSearch(uid, gid, mountIdx):
      return SysErrAccess

    let localPath = mountLocalPath(path, mounts[mountIdx].pathLen)
    if tmpfsFileSize(localPath) < 0 and not tmpfsIsDir(localPath):
      return SysErrNoEnt
    if not tmpfsCanExecute(uid, gid, localPath):
      return SysErrAccess

    return SysErrOk

  if isBinRoot(path):
    if appfsRootAllowsSearch(uid, gid):
      return SysErrOk

    return SysErrAccess

  if isBinPath(path):
    if not appfsRootAllowsSearch(uid, gid):
      return SysErrAccess
    if resolveAppfsPath(path) < 0:
      return SysErrNoEnt
    if not appfsFileAllowsExecute(uid, gid):
      return SysErrAccess

    return SysErrOk

  if isProcPath(path) or resolveDevPath(path) >= 0:
    return SysErrAccess

  let rawIdx = resolvePath(path)
  if rawIdx < 0:
    return SysErrNoEnt

  let searchedIdx = resolvePathWithSearch(uid, gid, path)
  if searchedIdx < 0 or searchedIdx != rawIdx:
    return SysErrAccess
  if not canExecuteNode(uid, gid, searchedIdx):
    return SysErrAccess

  SysErrOk


## Implements the fs can search dir path kernel helper.
proc fsCanSearchDirPath*(uid, gid: U32, path: cstring): bool =
  if not fsReady or path == nil:
    return false

  let mountIdx = findMount(path)
  if mountIdx >= 0 and mounts[mountIdx].backend == vfsTmpfs:
    return mountPointAllowsSearch(uid, gid, mountIdx) and
      tmpfsCanSearchDir(uid, gid, mountLocalPath(path, mounts[mountIdx].pathLen))

  if isBinRoot(path):
    return appfsRootAllowsSearch(uid, gid)

  if isProcPath(path):
    return true

  if resolveAppfsPath(path) >= 0 or resolveDevPath(path) >= 0:
    return false

  let idx = resolvePathWithSearch(uid, gid, path)
  canSearchNode(uid, gid, idx)


## Implements the fs can modify dir path kernel helper.
proc fsCanModifyDirPath*(uid, gid: U32, path: cstring): bool =
  if not fsReady or path == nil:
    return false

  let mountIdx = findMount(path)
  if mountIdx >= 0 and mounts[mountIdx].backend == vfsTmpfs:
    return mountPointAllowsSearch(uid, gid, mountIdx) and
      tmpfsCanModifyDir(uid, gid, mountLocalPath(path, mounts[mountIdx].pathLen))

  if isBinPath(path) or resolveAppfsPath(path) >= 0 or resolveDevPath(path) >= 0:
    return false

  if isProcPath(path):
    return false

  let idx = resolvePathWithSearch(uid, gid, path)
  canSearchNode(uid, gid, idx) and canWriteNode(uid, gid, idx)


## Implements the fs can modify parent path kernel helper.
proc fsCanModifyParentPath*(uid, gid: U32, path: cstring): bool =
  if not fsReady or path == nil:
    return false

  let mountIdx = findMount(path)
  if mountIdx >= 0 and mounts[mountIdx].backend == vfsTmpfs:
    return mountPointAllowsSearch(uid, gid, mountIdx) and
      tmpfsCanModifyParent(uid, gid, mountLocalPath(path, mounts[mountIdx].pathLen))

  if isBinPath(path) or resolveAppfsPath(path) >= 0 or resolveDevPath(path) >= 0:
    return false

  if isProcPath(path):
    return false

  var leaf: array[FsNameMax, char]
  let parent = resolveParentWithSearch(uid, gid, path, leaf)
  canSearchNode(uid, gid, parent) and canWriteNode(uid, gid, parent)


## Implements the sticky allows remove kernel helper.
proc stickyAllowsRemove(uid: U32, parent, target: int): bool =
  if parent < 0 or target < 0:
    return false
  if (superBlock.nodes[parent].mode and FsModeSticky) == U32(0):
    return true

  uid == RootUid or uid == superBlock.nodes[parent].uid or uid == superBlock.nodes[target].uid


## Implements the fs can remove path kernel helper.
proc fsCanRemovePath*(uid, gid: U32, path: cstring): bool =
  if not fsReady or path == nil:
    return false

  let mountIdx = findMount(path)
  if mountIdx >= 0 and mounts[mountIdx].backend == vfsTmpfs:
    return mountPointAllowsSearch(uid, gid, mountIdx) and
      tmpfsCanRemove(uid, gid, mountLocalPath(path, mounts[mountIdx].pathLen))

  if isBinPath(path) or resolveAppfsPath(path) >= 0 or resolveDevPath(path) >= 0:
    return false

  if isProcPath(path):
    return false

  var leaf: array[FsNameMax, char]
  let parent = resolveParentWithSearch(uid, gid, path, leaf)
  if not (canSearchNode(uid, gid, parent) and canWriteNode(uid, gid, parent)):
    return false

  let target = findChild(parent, cast[cstring](addr leaf[0]))
  target > 0 and stickyAllowsRemove(uid, parent, target)


## Implements the fs can chmod path kernel helper.
proc fsCanChmodPath*(uid, gid: U32, path: cstring): bool =
  if not fsReady or path == nil:
    return false

  let mountIdx = findMount(path)
  if mountIdx >= 0 and mounts[mountIdx].backend == vfsTmpfs:
    return mountPointAllowsSearch(uid, gid, mountIdx) and
      tmpfsCanChmod(uid, gid, mountLocalPath(path, mounts[mountIdx].pathLen))

  if isBinPath(path) or resolveAppfsPath(path) >= 0 or
      resolveDevPath(path) >= 0 or isProcPath(path):
    return false

  let idx = resolvePathWithSearch(uid, gid, path)
  idx >= 0 and (uid == RootUid or uid == superBlock.nodes[idx].uid)


## Fills node entry.
proc fillNodeEntry(idx: int, outEntry: ptr FsDirEntry) =
  outEntry.typ = superBlock.nodes[idx].typ
  outEntry.size = superBlock.nodes[idx].size
  outEntry.uid = superBlock.nodes[idx].uid
  outEntry.gid = superBlock.nodes[idx].gid
  outEntry.mode = superBlock.nodes[idx].mode

  var i = 0
  while i < FsDirEntryNameMax:
    outEntry.name[i] = superBlock.nodes[idx].name[i]
    inc i


## Fills appfs entry.
proc fillAppfsEntry(idx: int, outEntry: ptr FsDirEntry) =
  outEntry.typ = FsDirEntryTypeFile
  outEntry.size = appfsEntries[idx].size
  outEntry.uid = RootUid
  outEntry.gid = RootGid
  outEntry.mode = FsModeReadonlyFile

  var i = 0
  while i < FsDirEntryNameMax:
    outEntry.name[i] = appfsEntries[idx].name[i]
    inc i


## Fills dev entry.
proc fillDevEntry(idx: int, outEntry: ptr FsDirEntry) =
  outEntry.typ = FsDirEntryTypeFile
  outEntry.size = 0
  outEntry.uid = RootUid
  outEntry.gid = RootGid
  outEntry.mode = FsModeDeviceFile

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


## Fills virtual dir entry.
proc fillVirtualDirEntry(name: cstring, outEntry: ptr FsDirEntry) =
  outEntry.typ = FsDirEntryTypeDir
  outEntry.size = 0
  outEntry.uid = RootUid
  outEntry.gid = RootGid
  outEntry.mode = FsModeDirDefault

  var i = 0
  while i < FsDirEntryNameMax:
    if name[i] == '\0':
      break
    outEntry.name[i] = name[i]
    inc i

  while i < FsDirEntryNameMax:
    outEntry.name[i] = '\0'
    inc i


## Implements the fs read dir entry kernel helper.
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


## Implements the fs read dir entries kernel helper.
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


## Implements the fs is dir kernel helper.
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


## Implements the fs file size kernel helper.
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


## Implements the fs mkdir kernel helper.
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


## Implements the fs write text kernel helper.
proc fsWriteText*(path: cstring, data: cstring): int =
  var size = U64(0)
  while data[size] != '\0' and size < FsFileBlocks * BlockSize:
    inc size
  fsWriteFile(path, cast[pointer](data), size)


## Implements the fs write file kernel helper.
proc fsWriteFile*(path: cstring, data: pointer, size: U64): int =
  fsWriteFileWithFlags(path, data, size, SysFsWriteDefault)


## Implements the fs write file with flags kernel helper.
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


## Implements the fs unlink kernel helper.
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


## Implements the fs rmdir kernel helper.
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


## Returns whether descendant is true.
proc isDescendant(idx, maybeParent: int): bool =
  var current = idx
  while current > 0:
    if current == maybeParent:
      return true
    current = int(superBlock.nodes[current].parent)
  false


## Implements the fs rename kernel helper.
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


## Implements the fs chmod kernel helper.
proc fsChmod*(path: cstring, mode: U32): int =
  if not fsReady or path == nil:
    return -1
  if isBinPath(path) or resolveAppfsPath(path) >= 0 or
      resolveDevPath(path) >= 0 or isProcPath(path):
    return -1

  let mountIdx = findMount(path)
  if mountIdx >= 0 and mounts[mountIdx].backend == vfsTmpfs:
    return tmpfsChmod(mountLocalPath(path, mounts[mountIdx].pathLen), mode)

  let idx = resolvePath(path)
  if idx < 0:
    return -1

  superBlock.nodes[idx].mode = mode
  writeSuper()


## Implements the fs chown kernel helper.
proc fsChown*(path: cstring, uid, gid: U32): int =
  if not fsReady or path == nil:
    return -1
  if isBinPath(path) or resolveAppfsPath(path) >= 0 or
      resolveDevPath(path) >= 0 or isProcPath(path):
    return -1

  let mountIdx = findMount(path)
  if mountIdx >= 0 and mounts[mountIdx].backend == vfsTmpfs:
    return tmpfsChown(mountLocalPath(path, mounts[mountIdx].pathLen), uid, gid)

  let idx = resolvePath(path)
  if idx < 0:
    return -1

  superBlock.nodes[idx].uid = uid
  superBlock.nodes[idx].gid = gid
  writeSuper()


## Implements the fs read file kernel helper.
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


## Implements the fs read file range kernel helper.
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
