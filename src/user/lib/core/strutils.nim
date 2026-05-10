import ../../../lib/types


proc cstrlen*(s: cstring): U64 =
  if s == nil:
    return 0
  var n = U64(0)
  while s[n] != '\0':
    inc n
  n


proc streq*(a, b: cstring): bool =
  if a == nil or b == nil:
    return false
  var i = U64(0)
  while a[i] == b[i]:
    if a[i] == '\0':
      return true
    inc i
  false


proc startsWith2*(s: cstring, a, b: char): bool =
  s != nil and s[0] == a and s[1] == b


proc isEmpty*(s: cstring): bool =
  s == nil or s[0] == '\0'


proc startsWithPrefix*(s: cstring, prefix: cstring): bool =
  var i: U32 = 0

  while prefix[i] != '\0':
    if s[i] != prefix[i]:
      return false
    inc i
  true


proc isSpace*(ch: char): bool =
  ch == ' ' or ch == '\t' or ch == '\r' or ch == '\n'


proc isDigit*(ch: char): bool =
  ch >= '0' and ch <= '9'


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