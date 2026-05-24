## Initializes the filesystem tree and reports filesystem metadata.

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
    changed = true

  if writeFileBytes(idx, cast[pointer](data), size) < 0:
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
  fsChanged = ensureRootDirOwned(
    "usr",
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

  let userHomeIdx = resolvePath("/home/rkc")
  fsChanged = ensureChildDirOwned(
    userHomeIdx,
    "bin",
    UserUid,
    UserGid,
    FsModeDirDefault,
  ) or fsChanged
  fsChanged = ensureChildDirOwned(
    userHomeIdx,
    "src",
    UserUid,
    UserGid,
    FsModeDirDefault,
  ) or fsChanged

  let usrIdx = resolvePath("/usr")
  fsChanged = ensureChildDirOwned(
    usrIdx,
    "bin",
    RootUid,
    RootGid,
    FsModeDirDefault,
  ) or fsChanged
  fsChanged = ensureChildDirOwned(
    usrIdx,
    "src",
    RootUid,
    RootGid,
    FsModeDirDefault,
  ) or fsChanged
  fsChanged = ensureChildDirOwned(
    usrIdx,
    "include",
    RootUid,
    RootGid,
    FsModeDirDefault,
  ) or fsChanged
  fsChanged = ensureChildDirOwned(
    usrIdx,
    "lib",
    RootUid,
    RootGid,
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
      blocks += U64(superBlock.nodes[i].blockCount)
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
    setFsInfo(
      addr entries[count],
      cstring"rootfs",
      cstring"nfs3",
      cstring"/",
      BlockSize,
      U64(FsDataBlockCount),
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
