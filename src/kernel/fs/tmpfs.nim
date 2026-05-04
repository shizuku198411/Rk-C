import ../../kernel/console
import ../../lib/types

type
  U32 = uint32

const
  TmpfsMaxNodes = 16
  TmpfsNameMax = 16
  TmpfsFileMax = 512

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

proc printNodeName(idx: int) =
  print(cast[cstring](addr nodes[idx].name[0]))
  if nodes[idx].typ == TmpfsTypeDir:
    putChar('/')

proc tmpfsList*(path: cstring = "/"): int =
  if not ready:
    return -1

  let dir = resolvePath(path)
  if dir < 0:
    println("not found")
    return -1
  if nodes[dir].typ == TmpfsTypeFile:
    printNodeName(dir)
    putChar(' ')
    printUnsigned(U64(nodes[dir].size))
    println(" bytes")
    return 0

  var i = 0
  while i < TmpfsMaxNodes:
    if nodes[i].used != 0 and nodes[i].parent == U32(dir) and i != dir:
      printNodeName(i)
      if nodes[i].typ == TmpfsTypeFile:
        putChar(' ')
        printUnsigned(U64(nodes[i].size))
        print(" bytes")
      putChar('\n')
    inc i
  0

proc tmpfsCat*(path: cstring): int =
  if not ready:
    return -1
  let idx = resolvePath(path)
  if idx < 0 or nodes[idx].typ != TmpfsTypeFile:
    return -1

  var i = U32(0)
  while i < nodes[idx].size:
    putChar(nodes[idx].data[i])
    inc i
  if nodes[idx].size == 0 or nodes[idx].data[nodes[idx].size - 1] != '\n':
    putChar('\n')
  0

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
  var idx = resolvePath(path)
  if idx < 0:
    var leaf: array[TmpfsNameMax, char]
    let parent = resolveParent(path, leaf)
    if parent < 0 or nodes[parent].typ != TmpfsTypeDir:
      return -1
    idx = allocNode(parent, cast[cstring](addr leaf[0]), TmpfsTypeFile)

  if idx < 0 or nodes[idx].typ != TmpfsTypeFile:
    return -1

  var size = U32(0)
  while data[size] != '\0' and size < U32(TmpfsFileMax):
    nodes[idx].data[size] = data[size]
    inc size
  nodes[idx].size = size
  0
