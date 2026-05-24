## Handles tmpfs content operations, creation, deletion, and renaming.

## Implements the tmpfs read range kernel helper.
proc tmpfsReadRange*(path: cstring, dst: pointer, offset, capacity: U64): int =
  if not ready or dst == nil:
    return -1
  let idx = resolvePath(path)
  if idx < 0 or nodes[idx].typ != TmpfsTypeFile:
    return -1

  let size = U64(nodes[idx].size)
  if offset >= size:
    return 0

  var readLen = size - offset
  if readLen > capacity:
    readLen = capacity

  let outBuf = cast[ptr UncheckedArray[char]](dst)
  var i = U64(0)
  while i < readLen:
    outBuf[i] = nodes[idx].data[offset + i]
    inc i

  int(readLen)


## Implements the tmpfs read file kernel helper.
proc tmpfsReadFile*(path: cstring, dst: pointer, capacity: U64): int =
  if not ready or dst == nil:
    return -1
  let idx = resolvePath(path)
  if idx < 0 or nodes[idx].typ != TmpfsTypeFile:
    return -1

  let size = U64(nodes[idx].size)
  if size > capacity:
    return -1

  tmpfsReadRange(path, dst, U64(0), capacity)


## Implements the tmpfs mkdir kernel helper.
proc tmpfsMkdir*(path: cstring): int =
  if not ready:
    return -1
  var leaf: array[TmpfsNameMax, char]
  let parent = resolveParent(path, leaf)
  if parent < 0 or nodes[parent].typ != TmpfsTypeDir:
    return -1

  let idx = allocNode(parent, cast[cstring](addr leaf[0]), TmpfsTypeDir)
  if idx < 0:
    return -1
  0


## Implements the tmpfs unlink kernel helper.
proc tmpfsUnlink*(path: cstring): int =
  if not ready:
    return -1
  let idx = resolvePath(path)
  if idx <= 0 or nodes[idx].typ != TmpfsTypeFile:
    return -1

  nodes[idx] = TmpfsNode()
  0


## Implements the tmpfs rmdir kernel helper.
proc tmpfsRmdir*(path: cstring): int =
  if not ready:
    return -1
  let idx = resolvePath(path)
  if idx <= 0 or nodes[idx].typ != TmpfsTypeDir or hasChildren(idx):
    return -1

  nodes[idx] = TmpfsNode()
  0


## Returns whether descendant is true.
proc isDescendant(idx, maybeParent: int): bool =
  var current = idx
  while current > 0:
    if current == maybeParent:
      return true
    current = int(nodes[current].parent)
  false


## Implements the tmpfs rename kernel helper.
proc tmpfsRename*(oldPath, newPath: cstring): int =
  if not ready:
    return -1

  let src = resolvePath(oldPath)
  if src <= 0:
    return -1
  if resolvePath(newPath) >= 0:
    return -1

  var leaf: array[TmpfsNameMax, char]
  let newParent = resolveParent(newPath, leaf)
  if newParent < 0 or nodes[newParent].typ != TmpfsTypeDir:
    return -1
  if nodes[src].typ == TmpfsTypeDir and isDescendant(newParent, src):
    return -1

  nodes[src].parent = U32(newParent)
  discard copyCString(nodes[src].name, cast[cstring](addr leaf[0]))
  0


## Implements the tmpfs write text kernel helper.
proc tmpfsWriteText*(path: cstring, data: cstring): int =
  var size = U64(0)
  while data[size] != '\0' and size < U64(TmpfsFileMax):
    inc size
  tmpfsWriteBytes(path, cast[pointer](data), size)


## Implements the tmpfs write bytes kernel helper.
proc tmpfsWriteBytes*(path: cstring, data: pointer, size: U64): int =
  tmpfsWriteBytesWithFlags(path, data, size, SysFsWriteDefault)


## Implements the tmpfs write bytes with flags kernel helper.
proc tmpfsWriteBytesWithFlags*(path: cstring, data: pointer, size: U64, flags: U32): int =
  if data == nil and size > 0:
    return -1
  if size > U64(TmpfsFileMax):
    return -1
  if (flags and (not SysFsWriteKnownFlags)) != U32(0):
    return -1

  let mode = flags and (SysFsWriteOverwrite or SysFsWriteAppend)
  if mode == U32(0) or mode == (SysFsWriteOverwrite or SysFsWriteAppend):
    return -1

  var idx = resolvePath(path)
  if idx < 0:
    if (flags and SysFsWriteCreate) == U32(0):
      return -1

    var leaf: array[TmpfsNameMax, char]
    let parent = resolveParent(path, leaf)
    if parent < 0 or nodes[parent].typ != TmpfsTypeDir:
      return -1
    idx = allocNode(parent, cast[cstring](addr leaf[0]), TmpfsTypeFile)

  if idx < 0 or nodes[idx].typ != TmpfsTypeFile:
    return -1

  let src = cast[ptr UncheckedArray[char]](data)
  var dstOffset = U64(0)
  if (mode and SysFsWriteAppend) != U32(0):
    dstOffset = U64(nodes[idx].size)

  if dstOffset + size > U64(TmpfsFileMax):
    return -1

  var i = U64(0)
  while i < size:
    nodes[idx].data[dstOffset + i] = src[i]
    inc i

  if (mode and SysFsWriteAppend) != U32(0):
    nodes[idx].size = U32(dstOffset + size)
  else:
    nodes[idx].size = U32(size)
  0


## Implements the tmpfs range write kernel helper.
proc tmpfsWriteRange*(path: cstring, data: pointer, offset, size: U64): int =
  if not ready or path == nil or (data == nil and size > U64(0)):
    return -1
  if offset + size < offset or offset + size > U64(TmpfsFileMax):
    return -1

  let idx = resolvePath(path)
  if idx < 0 or nodes[idx].typ != TmpfsTypeFile:
    return -1

  var i = U64(nodes[idx].size)
  while i < offset:
    nodes[idx].data[i] = '\0'
    inc i

  let src = cast[ptr UncheckedArray[char]](data)
  i = U64(0)
  while i < size:
    nodes[idx].data[offset + i] = src[i]
    inc i

  if offset + size > U64(nodes[idx].size):
    nodes[idx].size = U32(offset + size)
  0
