## Defines node metadata defaults and permission-bit checks for rootfs nodes.

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


