## Implements on-disk rootfs allocation, lookup, and byte transfer primitives.

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


## Marks rootfs metadata as dirty without immediately writing it to disk.
##
## This is used by streaming/range writes so multiple small writes can be
## coalesced into one metadata flush on close or shutdown.
proc markSuperDirty() =
  fsMetaDirty = true
  inc fsMetaDeferredWrites


## Flushes dirty rootfs metadata if needed.
##
## Data blocks are still written immediately by the file write path.  This only
## defers the superblock/node/bitmap metadata update.
proc fsFlushMetadata*(): int =
  if not fsMetaDirty:
    return 0

  if writeSuper() < 0:
    return -1

  fsMetaDirty = false
  fsMetaDeferredWrites = U64(0)
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
      superBlock.nodes[i].startBlock = 0
      superBlock.nodes[i].blockCount = 0
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


## Returns the data block count required to store a byte length.
proc dataBlocksForSize(size: U64): U32 =
  if size == U64(0):
    return U32(0)

  U32((size + BlockSize - U64(1)) div BlockSize)


## Returns whether a rootfs data block is reserved in the allocation bitmap.
proc dataBlockUsed(relativeBlock: U32): bool =
  let byteIdx = relativeBlock div U32(8)
  let bit = relativeBlock mod U32(8)
  (superBlock.dataBitmap[byteIdx] and U8(U32(1) shl bit)) != U8(0)


## Marks or releases one rootfs data block in the allocation bitmap.
proc setDataBlockUsed(relativeBlock: U32, used: bool) =
  let byteIdx = relativeBlock div U32(8)
  let bit = relativeBlock mod U32(8)
  let mask = U8(U32(1) shl bit)
  if used:
    superBlock.dataBitmap[byteIdx] = superBlock.dataBitmap[byteIdx] or mask
  else:
    superBlock.dataBitmap[byteIdx] = superBlock.dataBitmap[byteIdx] and (not mask)


## Marks or releases a contiguous absolute rootfs data extent.
proc setExtentUsed(startBlock, blockCount: U32, used: bool) =
  if blockCount == U32(0):
    return

  var i = U32(0)
  while i < blockCount:
    let relative = startBlock + i - U32(FsDataStartBlock)
    setDataBlockUsed(relative, used)
    inc i


## Locates a free contiguous rootfs data extent.
proc findFreeExtent(blockCount: U32): U32 =
  if blockCount == U32(0):
    return U32(FsDataStartBlock)

  var begin = U32(0)
  while begin + blockCount <= U32(FsDataBlockCount):
    var available = true
    var i = U32(0)
    while i < blockCount:
      if dataBlockUsed(begin + i):
        available = false
        break
      inc i

    if available:
      return U32(FsDataStartBlock) + begin
    inc begin

  U32(0)


## Writes zeroes into every block of an extent before it is exposed or released.
proc zeroExtent(startBlock, blockCount: U32): int =
  clearBlock()
  var i = U32(0)
  while i < blockCount:
    if serviceBlockWrite(U64(startBlock + i), addr blockBuf[0]) < 0:
      return -1
    inc i

  0


## Resizes one file extent, relocating and preserving blocks when growth needs it.
proc resizeFileExtent(idx: int, requiredBlocks: U32, preserve: bool): int =
  let oldStart = superBlock.nodes[idx].startBlock
  let oldCount = superBlock.nodes[idx].blockCount
  if requiredBlocks == oldCount:
    return 0

  if requiredBlocks < oldCount:
    let releaseStart = oldStart + requiredBlocks
    let releaseCount = oldCount - requiredBlocks
    if zeroExtent(releaseStart, releaseCount) < 0:
      return -1
    setExtentUsed(releaseStart, releaseCount, false)
    superBlock.nodes[idx].blockCount = requiredBlocks
    if requiredBlocks == U32(0):
      superBlock.nodes[idx].startBlock = U32(0)
    return 0

  if oldCount > U32(0) and oldStart + requiredBlocks <= U32(AppfsStartBlock):
    var canExtend = true
    var i = oldCount
    while i < requiredBlocks:
      if dataBlockUsed(oldStart + i - U32(FsDataStartBlock)):
        canExtend = false
        break
      inc i

    if canExtend:
      let added = requiredBlocks - oldCount
      setExtentUsed(oldStart + oldCount, added, true)
      if zeroExtent(oldStart + oldCount, added) < 0:
        return -1
      superBlock.nodes[idx].blockCount = requiredBlocks
      return 0

  let newStart = findFreeExtent(requiredBlocks)
  if newStart == U32(0):
    return -1

  setExtentUsed(newStart, requiredBlocks, true)
  if zeroExtent(newStart, requiredBlocks) < 0:
    return -1

  if preserve:
    var i = U32(0)
    while i < oldCount:
      if serviceBlockRead(U64(oldStart + i), addr blockBuf[0]) < 0:
        return -1
      if serviceBlockWrite(U64(newStart + i), addr blockBuf[0]) < 0:
        return -1
      inc i

  if oldCount > U32(0):
    if zeroExtent(oldStart, oldCount) < 0:
      return -1
    setExtentUsed(oldStart, oldCount, false)

  superBlock.nodes[idx].startBlock = newStart
  superBlock.nodes[idx].blockCount = requiredBlocks
  0


## Writes a complete replacement value into one rootfs file node.
proc writeFileBytes(idx: int, data: pointer, size: U64): int =
  if data == nil and size > 0:
    return -1
  if dataBlocksForSize(size) > U32(FsDataBlockCount):
    return -1
  if resizeFileExtent(idx, dataBlocksForSize(size), false) < 0:
    return -1

  let src = cast[ptr UncheckedArray[U8]](data)
  var written = U64(0)
  var blk = U32(0)
  while blk < superBlock.nodes[idx].blockCount:
    clearBlock()
    var i = U64(0)
    while i < BlockSize and written < size:
      blockBuf[i] = src[written]
      inc i
      inc written
    if serviceBlockWrite(U64(superBlock.nodes[idx].startBlock + blk), addr blockBuf[0]) < 0:
      return -1
    inc blk

  superBlock.nodes[idx].size = U32(size)
  0


## Updates a byte range in one rootfs file, growing and zero-filling holes as needed.
proc writeFileRangeBytes(idx: int, data: pointer, offset, size: U64): int =
  if data == nil and size > U64(0):
    return -1
  if offset + size < offset:
    return -1

  let endOffset = offset + size
  if dataBlocksForSize(endOffset) > U32(FsDataBlockCount):
    return -1
  if resizeFileExtent(idx, dataBlocksForSize(endOffset), true) < 0:
    return -1

  let oldSize = U64(superBlock.nodes[idx].size)
  var cursor =
    if offset > oldSize:
      oldSize
    else:
      offset
  while cursor < offset:
    let blk = U32(cursor div BlockSize)
    let inBlk = cursor mod BlockSize
    if serviceBlockRead(U64(superBlock.nodes[idx].startBlock + blk), addr blockBuf[0]) < 0:
      return -1
    var chunk = BlockSize - inBlk
    if chunk > offset - cursor:
      chunk = offset - cursor
    var i = U64(0)
    while i < chunk:
      blockBuf[inBlk + i] = U8(0)
      inc i
    if serviceBlockWrite(U64(superBlock.nodes[idx].startBlock + blk), addr blockBuf[0]) < 0:
      return -1
    cursor += chunk

  let src = cast[ptr UncheckedArray[U8]](data)
  cursor = U64(0)
  while cursor < size:
    let position = offset + cursor
    let blk = U32(position div BlockSize)
    let inBlk = position mod BlockSize
    if serviceBlockRead(U64(superBlock.nodes[idx].startBlock + blk), addr blockBuf[0]) < 0:
      return -1
    var chunk = BlockSize - inBlk
    if chunk > size - cursor:
      chunk = size - cursor
    var i = U64(0)
    while i < chunk:
      blockBuf[inBlk + i] = src[cursor + i]
      inc i
    if serviceBlockWrite(U64(superBlock.nodes[idx].startBlock + blk), addr blockBuf[0]) < 0:
      return -1
    cursor += chunk

  if endOffset > oldSize:
    superBlock.nodes[idx].size = U32(endOffset)
  0
