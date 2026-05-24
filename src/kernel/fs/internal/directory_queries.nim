## Enumerates directories and answers filesystem node queries.

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


