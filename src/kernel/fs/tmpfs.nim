import ../../lib/types
import ../fs/dirent


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
    name: array[TmpfsNameMax, char]
    data: array[TmpfsFileMax, char]

var
  nodes: array[TmpfsMaxNodes, TmpfsNode]
  ready: bool


proc tmpfsWriteText*(path: cstring, data: cstring): int
proc tmpfsWriteBytes*(path: cstring, data: pointer, size: U64): int


proc hasChildren(idx: int): bool =
  var i = 0
  while i < TmpfsMaxNodes:
    if nodes[i].used != 0 and nodes[i].parent == U32(idx) and i != idx:
      return true
    inc i
  false


proc copyName(dst: var array[TmpfsNameMax, char], src: cstring) =
  var i = 0
  while i < TmpfsNameMax - 1 and src[i] != '\0':
    dst[i] = src[i]
    inc i
  while i < TmpfsNameMax:
    dst[i] = '\0'
    inc i


proc nameEq(node: TmpfsNode, name: cstring): bool =
  var i = 0
  while i < TmpfsNameMax:
    if node.name[i] != name[i]:
      return false
    if node.name[i] == '\0':
      return true
    inc i
  name[TmpfsNameMax] == '\0'


proc findChild(parent: int, name: cstring): int =
  var i = 0
  while i < TmpfsMaxNodes:
    if nodes[i].used != 0 and nodes[i].parent == U32(parent) and nameEq(nodes[i], name):
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
      copyName(nodes[i].name, name)
      return i
    inc i
  -1


proc readComponent(path: cstring, pos: var int, name: var array[TmpfsNameMax, char]): bool =
  while path[pos] == '/':
    inc pos
  if path[pos] == '\0':
    return false

  var i = 0
  while path[pos] != '\0' and path[pos] != '/':
    if i < TmpfsNameMax - 1:
      name[i] = path[pos]
      inc i
    inc pos
  while i < TmpfsNameMax:
    name[i] = '\0'
    inc i
  true


proc resolvePath(path: cstring): int =
  if path == nil or path[0] == '\0':
    return -1
  if path[0] == '/' and path[1] == '\0':
    return 0

  var pos = 0
  var current = 0
  var name: array[TmpfsNameMax, char]
  while readComponent(path, pos, name):
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
  while readComponent(path, pos, name):
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
  copyName(nodes[0].name, "/")
  ready = true


proc fillDirEntry(idx: int, outEntry: ptr FsDirEntry) =
  outEntry.typ = nodes[idx].typ
  outEntry.size = nodes[idx].size

  var i = 0
  while i < FsDirEntryNameMax:
    outEntry.name[i] = nodes[idx].name[i]
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

  var seen = U64(0)
  var i = 0
  while i < TmpfsMaxNodes:
    if nodes[i].used != 0 and nodes[i].parent == U32(dir) and i != dir:
      if seen == entryIndex:
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


proc tmpfsReadFile*(path: cstring, dst: pointer, capacity: U64): int =
  if not ready or dst == nil:
    return -1
  let idx = resolvePath(path)
  if idx < 0 or nodes[idx].typ != TmpfsTypeFile:
    return -1

  let size = U64(nodes[idx].size)
  if size > capacity:
    return -1

  let outBuf = cast[ptr UncheckedArray[char]](dst)
  var i = U64(0)
  while i < size:
    outBuf[i] = nodes[idx].data[i]
    inc i
  int(size)


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


proc tmpfsWriteText*(path: cstring, data: cstring): int =
  var size = U64(0)
  while data[size] != '\0' and size < U64(TmpfsFileMax):
    inc size
  tmpfsWriteBytes(path, cast[pointer](data), size)


proc tmpfsWriteBytes*(path: cstring, data: pointer, size: U64): int =
  if data == nil and size > 0:
    return -1
  if size > U64(TmpfsFileMax):
    return -1

  var idx = resolvePath(path)
  if idx < 0:
    var leaf: array[TmpfsNameMax, char]
    let parent = resolveParent(path, leaf)
    if parent < 0 or nodes[parent].typ != TmpfsTypeDir:
      return -1
    idx = allocNode(parent, cast[cstring](addr leaf[0]), TmpfsTypeFile)

  if idx < 0 or nodes[idx].typ != TmpfsTypeFile:
    return -1

  let src = cast[ptr UncheckedArray[char]](data)
  var i = U64(0)
  while i < size:
    nodes[idx].data[i] = src[i]
    inc i
  nodes[idx].size = U32(size)
  0
