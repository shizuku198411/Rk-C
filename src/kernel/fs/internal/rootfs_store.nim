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


