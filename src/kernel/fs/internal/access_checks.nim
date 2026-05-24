## Evaluates filesystem access, traversal, and metadata-change permissions.

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


