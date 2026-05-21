## Provides fixed-size C string copy and comparison helpers.
import types


## Copies cstring.
proc copyCString*(dst: var openArray[char], src: cstring): bool =
  if dst.len == 0:
    return false

  var i = 0
  while i + 1 < dst.len:
    if src == nil or src[i] == '\0':
      break
    dst[i] = src[i]
    inc i

  let fits = src == nil or src[i] == '\0'
  while i < dst.len:
    dst[i] = '\0'
    inc i

  fits


## Copies chars.
proc copyChars*(dst: var openArray[char], src: openArray[char]) =
  var i = 0
  while i < dst.len and i < src.len:
    dst[i] = src[i]
    inc i

  while i < dst.len:
    dst[i] = '\0'
    inc i


## Implements the cstring eq helper.
proc cstringEq*(a, b: cstring): bool =
  if a == nil or b == nil:
    return false

  var i = 0
  while a[i] == b[i]:
    if a[i] == '\0':
      return true
    inc i

  false


## Implements the fixed cstring eq helper.
proc fixedCStringEq*(src: openArray[char], expected: cstring): bool =
  if expected == nil:
    return false

  var i = 0
  while i < src.len:
    if src[i] != expected[i]:
      return false
    if src[i] == '\0':
      return true
    inc i

  expected[src.len] == '\0'


## Implements the fixed cstring eq helper.
proc fixedCStringEq*(src: ptr UncheckedArray[char], capacity: int, expected: cstring): bool =
  if src == nil or expected == nil:
    return false

  var i = 0
  while i < capacity:
    if src[i] != expected[i]:
      return false
    if src[i] == '\0':
      return true
    inc i

  expected[capacity] == '\0'


## Implements the cstrlen helper.
proc cstrlen*(s: cstring): U64 =
  if s == nil:
    return 0

  var n = 0
  while s[n] != '\0':
    inc n

  U64(n)
