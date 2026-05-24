## Implements the in-memory tmpfs filesystem backend.
import ../../lib/fixed_string
import ../../lib/fs_permissions
import ../../lib/syscall_types
import ../../lib/types
import ../../lib/user_ids
import ../fs/dirent
import ../lib/path


const
  TmpfsMaxNodes = 16
  TmpfsNameMax = 16
  TmpfsFileMax = 4096

  TmpfsTypeFile = U32(1)
  TmpfsTypeDir = U32(2)

type
  TmpfsNode = object
    used: U32
    typ: U32
    parent: U32
    size: U32
    uid: U32
    gid: U32
    mode: U32
    name: array[TmpfsNameMax, char]
    data: array[TmpfsFileMax, char]

var
  nodes: array[TmpfsMaxNodes, TmpfsNode]
  ready: bool


## Implements the tmpfs write text kernel helper.
proc tmpfsWriteText*(path: cstring, data: cstring): int
## Implements the tmpfs write bytes kernel helper.
proc tmpfsWriteBytes*(path: cstring, data: pointer, size: U64): int
## Implements the tmpfs write bytes with flags kernel helper.
proc tmpfsWriteBytesWithFlags*(path: cstring, data: pointer, size: U64, flags: U32): int


## Implements the default node mode kernel helper.
proc defaultNodeMode(typ: U32): U32 =
  if typ == TmpfsTypeFile:
    return FsModeFileDefault

  FsModePublicDir


## Initializes node metadata.
proc initNodeMetadata(node: ptr TmpfsNode, typ: U32) =
  if node == nil:
    return

  node.uid = RootUid
  node.gid = RootGid
  node.mode = defaultNodeMode(typ)


## Checks whether read node is allowed.
proc canReadNode(uid, gid: U32, idx: int): bool =
  idx >= 0 and idx < TmpfsMaxNodes and nodes[idx].used != U32(0) and
    fsModeAllowsRead(nodes[idx].uid, nodes[idx].gid, nodes[idx].mode, uid, gid)


## Checks whether write node is allowed.
proc canWriteNode(uid, gid: U32, idx: int): bool =
  idx >= 0 and idx < TmpfsMaxNodes and nodes[idx].used != U32(0) and
    fsModeAllowsWrite(nodes[idx].uid, nodes[idx].gid, nodes[idx].mode, uid, gid)


## Checks whether execute node is allowed.
proc canExecuteNode(uid, gid: U32, idx: int): bool =
  idx >= 0 and idx < TmpfsMaxNodes and nodes[idx].used != U32(0) and
    fsModeAllowsExecute(nodes[idx].uid, nodes[idx].gid, nodes[idx].mode, uid, gid)


## Checks whether search node is allowed.
proc canSearchNode(uid, gid: U32, idx: int): bool =
  idx >= 0 and idx < TmpfsMaxNodes and nodes[idx].used != U32(0) and
    nodes[idx].typ == TmpfsTypeDir and canExecuteNode(uid, gid, idx)


## Implements the tmpfs max nodes kernel helper.
proc tmpfsMaxNodes*(): U64 =
  U64(TmpfsMaxNodes)


## Implements the tmpfs max file bytes kernel helper.
proc tmpfsMaxFileBytes*(): U64 =
  U64(TmpfsFileMax)


## Implements the tmpfs used nodes kernel helper.
proc tmpfsUsedNodes*(): U64 =
  var count = U64(0)
  var i = 0
  while i < TmpfsMaxNodes:
    if nodes[i].used != 0:
      inc count
    inc i
  count


## Implements the tmpfs used blocks kernel helper.
proc tmpfsUsedBlocks*(blockSize: U64): U64 =
  var blocks = U64(0)
  var i = 0
  while i < TmpfsMaxNodes:
    if nodes[i].used != 0 and nodes[i].typ == TmpfsTypeFile:
      blocks += (U64(nodes[i].size) + blockSize - U64(1)) div blockSize
    inc i
  blocks


## Returns whether children is present.
proc hasChildren(idx: int): bool =
  var i = 0
  while i < TmpfsMaxNodes:
    if nodes[i].used != 0 and nodes[i].parent == U32(idx) and i != idx:
      return true
    inc i
  false


## Finds child.
proc findChild(parent: int, name: cstring): int =
  var i = 0
  while i < TmpfsMaxNodes:
    if nodes[i].used != 0 and nodes[i].parent == U32(parent) and
        fixedCStringEq(nodes[i].name, name):
      return i
    inc i
  -1


## Allocates node.
proc allocNode(parent: int, name: cstring, typ: U32): int =
  let existing = findChild(parent, name)
  if existing >= 0:
    return existing

  var i = 1
  while i < TmpfsMaxNodes:
    if nodes[i].used == 0:
      nodes[i].used = 1
      nodes[i].typ = typ
      nodes[i].parent = U32(parent)
      nodes[i].size = 0
      initNodeMetadata(addr nodes[i], typ)
      discard copyCString(nodes[i].name, name)
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
  var name: array[TmpfsNameMax, char]
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
  var name: array[TmpfsNameMax, char]
  while readPathComponent(path, pos, name):
    if not canSearchNode(uid, gid, current):
      return -1

    let next = findChild(current, cast[cstring](addr name[0]))
    if next < 0:
      return -1
    current = next
  current


## Resolves parent.
proc resolveParent(path: cstring, leaf: var array[TmpfsNameMax, char]): int =
  if path == nil or path[0] == '\0':
    return -1

  var pos = 0
  var current = 0
  var name: array[TmpfsNameMax, char]
  while readPathComponent(path, pos, name):
    if path[pos] == '\0':
      leaf = name
      return current
    let next = findChild(current, cast[cstring](addr name[0]))
    if next < 0 or nodes[next].typ != TmpfsTypeDir:
      return -1
    current = next
  -1


## Resolves parent with search.
proc resolveParentWithSearch(uid, gid: U32, path: cstring, leaf: var array[TmpfsNameMax, char]): int =
  if path == nil or path[0] == '\0':
    return -1

  var pos = 0
  var current = 0
  var name: array[TmpfsNameMax, char]
  while readPathComponent(path, pos, name):
    if not canSearchNode(uid, gid, current):
      return -1

    if path[pos] == '\0':
      leaf = name
      return current
    let next = findChild(current, cast[cstring](addr name[0]))
    if next < 0 or nodes[next].typ != TmpfsTypeDir:
      return -1
    current = next
  -1


## Implements the tmpfs init kernel helper.
proc tmpfsInit*() =
  nodes = default(array[TmpfsMaxNodes, TmpfsNode])
  nodes[0].used = 1
  nodes[0].typ = TmpfsTypeDir
  nodes[0].parent = 0
  initNodeMetadata(addr nodes[0], TmpfsTypeDir)
  nodes[0].mode = FsModeStickyPublicDir
  discard copyCString(nodes[0].name, "/")
  ready = true


## Includes handles tmpfs enumeration, lookup queries, and access metadata changes.
include ./tmpfs_internal/directory_access


## Includes handles tmpfs content operations, creation, deletion, and renaming.
include ./tmpfs_internal/file_ops
