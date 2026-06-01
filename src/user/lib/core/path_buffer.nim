## Provides fixed-size path buffer helpers for user applications.
import ./strutils


## Clears a fixed-size C string buffer.
proc clearBuffer*(dst: ptr UncheckedArray[char], capacity: int) =
  if dst == nil:
    return

  var i = 0
  while i < capacity:
    dst[i] = '\0'
    inc i


## Appends one character to a fixed-size C string buffer.
proc appendChar*(dst: ptr UncheckedArray[char], capacity: int, pos: var int, ch: char): bool =
  if dst == nil or capacity <= 0 or pos + 1 >= capacity:
    return false

  dst[pos] = ch
  inc pos
  dst[pos] = '\0'
  true


## Appends a C string to a fixed-size C string buffer.
proc appendCString*(dst: ptr UncheckedArray[char], capacity: int, pos: var int, src: cstring): bool =
  if dst == nil or src == nil:
    return false

  var i = 0
  while src[i] != '\0':
    if not appendChar(dst, capacity, pos, src[i]):
      return false
    inc i

  true


## Copies a C string into a fixed-size C string buffer.
proc copyCStringInto*(dst: ptr UncheckedArray[char], capacity: int, src: cstring): bool =
  clearBuffer(dst, capacity)

  var pos = 0
  appendCString(dst, capacity, pos, src)


## Returns a C string view of the final path component.
proc pathBasename*(path: cstring): cstring =
  if isEmpty(path):
    return path

  var endPos = 0
  while path[endPos] != '\0':
    inc endPos

  while endPos > 1 and path[endPos - 1] == '/':
    dec endPos

  var start = endPos
  while start > 0 and path[start - 1] != '/':
    dec start

  cast[cstring](addr path[start])


## Joins a directory path and a leaf name into a fixed-size path buffer.
proc joinPath*(dir, name: cstring, dst: ptr UncheckedArray[char], capacity: int): cstring =
  if dir == nil or name == nil or dst == nil or capacity <= 0:
    return nil

  clearBuffer(dst, capacity)
  var pos = 0

  if dir[0] == '/' and dir[1] == '\0':
    if not appendChar(dst, capacity, pos, '/'):
      return nil
  else:
    if not appendCString(dst, capacity, pos, dir):
      return nil

    if pos > 0 and dst[pos - 1] != '/':
      if not appendChar(dst, capacity, pos, '/'):
        return nil

  var i = 0
  while name[i] != '\0':
    if name[i] == '/':
      break
    if not appendChar(dst, capacity, pos, name[i]):
      return nil
    inc i

  cast[cstring](dst)


## Builds /bin/<command> into a fixed-size path buffer.
proc buildBinPath*(command: cstring, dst: ptr UncheckedArray[char], capacity: int): cstring =
  if command == nil or dst == nil or capacity <= 0:
    return nil

  clearBuffer(dst, capacity)
  var pos = 0
  if not appendCString(dst, capacity, pos, cstring"/bin/"):
    return nil
  if not appendCString(dst, capacity, pos, command):
    return nil

  cast[cstring](dst)
