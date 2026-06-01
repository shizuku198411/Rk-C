## Provides fixed-buffer helpers used by shell command completion.


## Clears a fixed char buffer.
proc clearArray*(buf: ptr UncheckedArray[char], cap: int) =
  if buf == nil:
    return

  var i = 0
  while i < cap:
    buf[i] = '\0'
    inc i


## Copies a C string into a fixed char buffer.
proc copyToArray*(dst: ptr UncheckedArray[char], cap: int, src: cstring): bool =
  if dst == nil or cap <= 0 or src == nil:
    return false

  clearArray(dst, cap)

  var i = 0
  while src[i] != '\0':
    if i + 1 >= cap:
      return false

    dst[i] = src[i]
    inc i

  dst[i] = '\0'
  true


## Appends a C string to a fixed char buffer at the given position.
proc appendToArray*(dst: ptr UncheckedArray[char], cap: int, pos: var int, src: cstring): bool =
  if dst == nil or cap <= 0 or src == nil:
    return false

  var i = 0
  while src[i] != '\0':
    if pos + 1 >= cap:
      return false

    dst[pos] = src[i]
    inc pos
    inc i

  dst[pos] = '\0'
  true


## Appends one character to a fixed char buffer at the given position.
proc appendCharToArray*(dst: ptr UncheckedArray[char], cap: int, pos: var int, ch: char): bool =
  if dst == nil or cap <= 0:
    return false

  if pos + 1 >= cap:
    return false

  dst[pos] = ch
  inc pos
  dst[pos] = '\0'
  true


## Returns the byte length of a C string.
proc cstringLen*(s: cstring): int =
  if s == nil:
    return 0

  var i = 0
  while s[i] != '\0':
    inc i

  i


## Returns true when name starts with prefix.
proc startsWithCString*(name, prefix: cstring): bool =
  if name == nil or prefix == nil:
    return false

  var i = 0
  while prefix[i] != '\0':
    if name[i] != prefix[i]:
      return false
    inc i

  true


## Returns true when a C string contains a slash.
proc hasSlash*(s: cstring): bool =
  if s == nil:
    return false

  var i = 0
  while s[i] != '\0':
    if s[i] == '/':
      return true
    inc i

  false
