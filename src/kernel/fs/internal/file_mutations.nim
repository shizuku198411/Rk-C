## Performs rootfs mutations and file-content reads and writes.

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
  while data[size] != '\0' and size < U64(FsDataBlockCount) * BlockSize:
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
  if size > U64(SysFsDataMax):
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

  let rc =
    if (mode and SysFsWriteAppend) != U32(0):
      writeFileRangeBytes(idx, data, U64(superBlock.nodes[idx].size), size)
    else:
      writeFileBytes(idx, data, size)
  if rc < 0:
    return -1
  writeSuper()


## Implements range writes used by descriptor-based streaming I/O.
proc fsWriteFileRange*(path: cstring, data: pointer, offset, size: U64): int =
  if not fsReady or path == nil:
    return -1
  if isBinPath(path) or (data == nil and size > U64(0)):
    return -1

  let mountIdx = findMount(path)
  if mountIdx >= 0 and mounts[mountIdx].backend == vfsTmpfs:
    return tmpfsWriteRange(mountLocalPath(path, mounts[mountIdx].pathLen), data, offset, size)

  let idx = resolvePath(path)
  if idx < 0 or superBlock.nodes[idx].typ != FsTypeFile:
    return -1
  if writeFileRangeBytes(idx, data, offset, size) < 0:
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

  if resizeFileExtent(idx, U32(0), false) < 0:
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
  while done < size and blk < U64(node.blockCount):
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
    if blk >= U64(node.blockCount):
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
