## Provides small string parsing and inspection helpers for userland.
import ../../../lib/fixed_string
import ../../../lib/types

export fixed_string


## Returns whether with2.
proc startsWith2*(s: cstring, a, b: char): bool =
  s != nil and s[0] == a and s[1] == b


## Returns whether empty is true.
proc isEmpty*(s: cstring): bool =
  s == nil or s[0] == '\0'


## Returns whether with prefix.
proc startsWithPrefix*(s: cstring, prefix: cstring): bool =
  var i: U32 = 0

  while prefix[i] != '\0':
    if s[i] != prefix[i]:
      return false
    inc i
  true


## Implements the cstring contains helper.
proc cstringContains*(s: ptr UncheckedArray[char], needle: cstring): bool =
  if s == nil or needle == nil:
    return false

  var i = U32(0)
  while s[i] != '\0':
    var j = U32(0)
    while needle[j] != '\0' and s[i + j] == needle[j]:
      inc j
    if needle[j] == '\0':
      return true
    inc i

  false


## Returns whether space is true.
proc isSpace*(ch: char): bool =
  ch == ' ' or ch == '\t' or ch == '\r' or ch == '\n'


## Returns whether digit is true.
proc isDigit*(ch: char): bool =
  ch >= '0' and ch <= '9'


## Gets line.
proc getLine*(src: ptr char, srcSize: int, pos: var int, dst: ptr char, dstSize: int): int =
  var lineLen = 0

  if pos >= srcSize:
    return 0

  let srcArr = cast[ptr UncheckedArray[char]](src)
  let dstArr = cast[ptr UncheckedArray[char]](dst)

  while pos < srcSize and srcArr[pos] != '\n' and srcArr[pos] != '\0':
    if srcArr[pos] != '\r':
      if lineLen < dstSize - 1:
        dstArr[lineLen] = srcArr[pos]
        inc lineLen

    inc pos

  dstArr[lineLen] = '\0'

  if pos < srcSize and srcArr[pos] == '\n':
    inc pos

  lineLen


## Parses u64.
proc parseU64*(s: cstring, outValue: var U64): bool =
  var
    pos = U32(0)
    value = U64(0)
    found = false
  
  while isSpace(s[pos]):
    inc pos
  
  while isDigit(s[pos]):
    found = true
    let digit = U64(ord(s[pos]) - ord('0'))

    # check overflow
    if value > (high(U64) - digit) div U64(10):
      return false
    
    value = value * U64(10) + digit
    inc pos

  if not found:
    return false

  while isSpace(s[pos]):
    inc pos
  
  if s[pos] != '\0':
    return false

  outValue = value
  true


## Parses u32.
proc parseU32*(s: cstring, outValue: var U32): bool =
  var value = U64(0)
  if not parseU64(s, value):
    return false
  if value > U64(high(U32)):
    return false

  outValue = U32(value)
  true
