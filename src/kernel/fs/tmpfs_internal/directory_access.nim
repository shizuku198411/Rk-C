## Handles tmpfs enumeration, lookup queries, and access metadata changes.

## Fills dir entry.
proc fillDirEntry(idx: int, outEntry: ptr FsDirEntry) =
  outEntry.typ = nodes[idx].typ
  outEntry.size = nodes[idx].size
  outEntry.uid = nodes[idx].uid
  outEntry.gid = nodes[idx].gid
  outEntry.mode = nodes[idx].mode

  var i = 0
  while i < FsDirEntryNameMax:
    outEntry.name[i] = nodes[idx].name[i]
    inc i


## Fills virtual dir entry.
proc fillVirtualDirEntry(name: cstring, outEntry: ptr FsDirEntry) =
  outEntry.typ = FsDirEntryTypeDir
  outEntry.size = 0
  outEntry.uid = RootUid
  outEntry.gid = RootGid
  outEntry.mode = FsModePublicDir

  var i = 0
  while i < FsDirEntryNameMax:
    if name[i] == '\0':
      break
    outEntry.name[i] = name[i]
    inc i

  while i < FsDirEntryNameMax:
    outEntry.name[i] = '\0'
    inc i


## Implements the tmpfs read dir entry kernel helper.
proc tmpfsReadDirEntry*(path: cstring, entryIndex: U64, outEntry: ptr FsDirEntry): int =
  if not ready or outEntry == nil:
    return -1

  let dir = resolvePath(path)
  if dir < 0:
    return -1

  if nodes[dir].typ == TmpfsTypeFile:
    if entryIndex != 0:
      return 0
    fillDirEntry(dir, outEntry)
    return 1

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
  while i < TmpfsMaxNodes:
    if nodes[i].used != 0 and nodes[i].parent == U32(dir) and i != dir:
      if seen == realEntryIndex:
        fillDirEntry(i, outEntry)
        return 1
      inc seen
    inc i
  0


## Implements the tmpfs is dir kernel helper.
proc tmpfsIsDir*(path: cstring): bool =
  if not ready:
    return false
  let idx = resolvePath(path)
  idx >= 0 and nodes[idx].typ == TmpfsTypeDir


## Implements the tmpfs file size kernel helper.
proc tmpfsFileSize*(path: cstring): int =
  if not ready:
    return -1
  let idx = resolvePath(path)
  if idx < 0 or nodes[idx].typ != TmpfsTypeFile:
    return -1

  int(nodes[idx].size)


## Implements the tmpfs can read kernel helper.
proc tmpfsCanRead*(uid, gid: U32, path: cstring): bool =
  let idx = resolvePathWithSearch(uid, gid, path)
  canReadNode(uid, gid, idx)


## Implements the tmpfs can write kernel helper.
proc tmpfsCanWrite*(uid, gid: U32, path: cstring): bool =
  let idx = resolvePathWithSearch(uid, gid, path)
  canWriteNode(uid, gid, idx)


## Implements the tmpfs can execute kernel helper.
proc tmpfsCanExecute*(uid, gid: U32, path: cstring): bool =
  let idx = resolvePathWithSearch(uid, gid, path)
  canExecuteNode(uid, gid, idx)


## Implements the tmpfs can search dir kernel helper.
proc tmpfsCanSearchDir*(uid, gid: U32, path: cstring): bool =
  let idx = resolvePathWithSearch(uid, gid, path)
  canSearchNode(uid, gid, idx)


## Implements the tmpfs can modify dir kernel helper.
proc tmpfsCanModifyDir*(uid, gid: U32, path: cstring): bool =
  let idx = resolvePathWithSearch(uid, gid, path)
  canSearchNode(uid, gid, idx) and canWriteNode(uid, gid, idx)


## Implements the tmpfs can modify parent kernel helper.
proc tmpfsCanModifyParent*(uid, gid: U32, path: cstring): bool =
  var leaf: array[TmpfsNameMax, char]
  let parent = resolveParentWithSearch(uid, gid, path, leaf)
  canSearchNode(uid, gid, parent) and canWriteNode(uid, gid, parent)


## Implements the sticky allows remove kernel helper.
proc stickyAllowsRemove(uid: U32, parent, target: int): bool =
  if parent < 0 or target < 0:
    return false
  if (nodes[parent].mode and FsModeSticky) == U32(0):
    return true

  uid == RootUid or uid == nodes[parent].uid or uid == nodes[target].uid


## Implements the tmpfs can remove kernel helper.
proc tmpfsCanRemove*(uid, gid: U32, path: cstring): bool =
  var leaf: array[TmpfsNameMax, char]
  let parent = resolveParentWithSearch(uid, gid, path, leaf)
  if not (canSearchNode(uid, gid, parent) and canWriteNode(uid, gid, parent)):
    return false

  let target = findChild(parent, cast[cstring](addr leaf[0]))
  target > 0 and stickyAllowsRemove(uid, parent, target)


## Implements the tmpfs can chmod kernel helper.
proc tmpfsCanChmod*(uid, gid: U32, path: cstring): bool =
  let idx = resolvePathWithSearch(uid, gid, path)
  idx >= 0 and (uid == RootUid or uid == nodes[idx].uid)


## Implements the tmpfs chmod kernel helper.
proc tmpfsChmod*(path: cstring, mode: U32): int =
  let idx = resolvePath(path)
  if idx < 0:
    return -1

  nodes[idx].mode = mode
  0


## Implements the tmpfs chown kernel helper.
proc tmpfsChown*(path: cstring, uid, gid: U32): int =
  let idx = resolvePath(path)
  if idx < 0:
    return -1

  nodes[idx].uid = uid
  nodes[idx].gid = gid
  0


