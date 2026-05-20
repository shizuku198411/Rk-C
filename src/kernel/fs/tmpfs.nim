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


proc tmpfsWriteText*(path: cstring, data: cstring): int
proc tmpfsWriteBytes*(path: cstring, data: pointer, size: U64): int
proc tmpfsWriteBytesWithFlags*(path: cstring, data: pointer, size: U64, flags: U32): int


proc defaultNodeMode(typ: U32): U32 =
  if typ == TmpfsTypeFile:
    return FsModeFileDefault

  FsModePublicDir


proc initNodeMetadata(node: ptr TmpfsNode, typ: U32) =
  if node == nil:
    return

  node.uid = RootUid
  node.gid = RootGid
  node.mode = defaultNodeMode(typ)


proc canReadNode(uid, gid: U32, idx: int): bool =
  idx >= 0 and idx < TmpfsMaxNodes and nodes[idx].used != U32(0) and
    fsModeAllowsRead(nodes[idx].uid, nodes[idx].gid, nodes[idx].mode, uid, gid)


proc canWriteNode(uid, gid: U32, idx: int): bool =
  idx >= 0 and idx < TmpfsMaxNodes and nodes[idx].used != U32(0) and
    fsModeAllowsWrite(nodes[idx].uid, nodes[idx].gid, nodes[idx].mode, uid, gid)


proc canExecuteNode(uid, gid: U32, idx: int): bool =
  idx >= 0 and idx < TmpfsMaxNodes and nodes[idx].used != U32(0) and
    fsModeAllowsExecute(nodes[idx].uid, nodes[idx].gid, nodes[idx].mode, uid, gid)


proc canSearchNode(uid, gid: U32, idx: int): bool =
  idx >= 0 and idx < TmpfsMaxNodes and nodes[idx].used != U32(0) and
    nodes[idx].typ == TmpfsTypeDir and canExecuteNode(uid, gid, idx)


proc tmpfsMaxNodes*(): U64 =
  U64(TmpfsMaxNodes)


proc tmpfsMaxFileBytes*(): U64 =
  U64(TmpfsFileMax)


proc tmpfsUsedNodes*(): U64 =
  var count = U64(0)
  var i = 0
  while i < TmpfsMaxNodes:
    if nodes[i].used != 0:
      inc count
    inc i
  count


proc tmpfsUsedBlocks*(blockSize: U64): U64 =
  var blocks = U64(0)
  var i = 0
  while i < TmpfsMaxNodes:
    if nodes[i].used != 0 and nodes[i].typ == TmpfsTypeFile:
      blocks += (U64(nodes[i].size) + blockSize - U64(1)) div blockSize
    inc i
  blocks


proc hasChildren(idx: int): bool =
  var i = 0
  while i < TmpfsMaxNodes:
    if nodes[i].used != 0 and nodes[i].parent == U32(idx) and i != idx:
      return true
    inc i
  false


proc findChild(parent: int, name: cstring): int =
  var i = 0
  while i < TmpfsMaxNodes:
    if nodes[i].used != 0 and nodes[i].parent == U32(parent) and
        fixedCStringEq(nodes[i].name, name):
      return i
    inc i
  -1


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


proc tmpfsInit*() =
  nodes = default(array[TmpfsMaxNodes, TmpfsNode])
  nodes[0].used = 1
  nodes[0].typ = TmpfsTypeDir
  nodes[0].parent = 0
  initNodeMetadata(addr nodes[0], TmpfsTypeDir)
  discard copyCString(nodes[0].name, "/")
  ready = true


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


proc tmpfsIsDir*(path: cstring): bool =
  if not ready:
    return false
  let idx = resolvePath(path)
  idx >= 0 and nodes[idx].typ == TmpfsTypeDir


proc tmpfsFileSize*(path: cstring): int =
  if not ready:
    return -1
  let idx = resolvePath(path)
  if idx < 0 or nodes[idx].typ != TmpfsTypeFile:
    return -1

  int(nodes[idx].size)


proc tmpfsCanRead*(uid, gid: U32, path: cstring): bool =
  let idx = resolvePathWithSearch(uid, gid, path)
  canReadNode(uid, gid, idx)


proc tmpfsCanWrite*(uid, gid: U32, path: cstring): bool =
  let idx = resolvePathWithSearch(uid, gid, path)
  canWriteNode(uid, gid, idx)


proc tmpfsCanExecute*(uid, gid: U32, path: cstring): bool =
  let idx = resolvePathWithSearch(uid, gid, path)
  canExecuteNode(uid, gid, idx)


proc tmpfsCanSearchDir*(uid, gid: U32, path: cstring): bool =
  let idx = resolvePathWithSearch(uid, gid, path)
  canSearchNode(uid, gid, idx)


proc tmpfsCanModifyDir*(uid, gid: U32, path: cstring): bool =
  let idx = resolvePathWithSearch(uid, gid, path)
  canSearchNode(uid, gid, idx) and canWriteNode(uid, gid, idx)


proc tmpfsCanModifyParent*(uid, gid: U32, path: cstring): bool =
  var leaf: array[TmpfsNameMax, char]
  let parent = resolveParentWithSearch(uid, gid, path, leaf)
  canSearchNode(uid, gid, parent) and canWriteNode(uid, gid, parent)


proc tmpfsCanChmod*(uid, gid: U32, path: cstring): bool =
  let idx = resolvePathWithSearch(uid, gid, path)
  idx >= 0 and (uid == RootUid or uid == nodes[idx].uid)


proc tmpfsChmod*(path: cstring, mode: U32): int =
  let idx = resolvePath(path)
  if idx < 0:
    return -1

  nodes[idx].mode = mode
  0


proc tmpfsChown*(path: cstring, uid, gid: U32): int =
  let idx = resolvePath(path)
  if idx < 0:
    return -1

  nodes[idx].uid = uid
  nodes[idx].gid = gid
  0


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


proc tmpfsUnlink*(path: cstring): int =
  if not ready:
    return -1
  let idx = resolvePath(path)
  if idx <= 0 or nodes[idx].typ != TmpfsTypeFile:
    return -1

  nodes[idx] = TmpfsNode()
  0


proc tmpfsRmdir*(path: cstring): int =
  if not ready:
    return -1
  let idx = resolvePath(path)
  if idx <= 0 or nodes[idx].typ != TmpfsTypeDir or hasChildren(idx):
    return -1

  nodes[idx] = TmpfsNode()
  0


proc isDescendant(idx, maybeParent: int): bool =
  var current = idx
  while current > 0:
    if current == maybeParent:
      return true
    current = int(nodes[current].parent)
  false


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


proc tmpfsWriteText*(path: cstring, data: cstring): int =
  var size = U64(0)
  while data[size] != '\0' and size < U64(TmpfsFileMax):
    inc size
  tmpfsWriteBytes(path, cast[pointer](data), size)


proc tmpfsWriteBytes*(path: cstring, data: pointer, size: U64): int =
  tmpfsWriteBytesWithFlags(path, data, size, SysFsWriteDefault)


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
