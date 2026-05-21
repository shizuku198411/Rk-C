## Provides fixed-size path manipulation helpers for kernel code.
proc readPathComponent*(path: cstring, pos: var int, name: var openArray[char]): bool =
  if path == nil or name.len == 0:
    return false

  while path[pos] == '/':
    inc pos
  if path[pos] == '\0':
    return false

  var i = 0
  while path[pos] != '\0' and path[pos] != '/':
    if i + 1 < name.len:
      name[i] = path[pos]
      inc i
    inc pos

  while i < name.len:
    name[i] = '\0'
    inc i

  true
