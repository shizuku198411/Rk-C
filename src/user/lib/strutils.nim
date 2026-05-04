import ../../lib/types

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
