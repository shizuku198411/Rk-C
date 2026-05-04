import types

proc strcmp*(s1: cstring, s2: cstring): cint {.exportc: "strcmp", cdecl.} =
  var i = 0

  while s1[i] != '\0' and s1[i] == s2[i]:
    inc i

  cint(ord(s1[i])) - cint(ord(s2[i]))

proc strlen*(s: cstring): CSize {.exportc: "strlen", cdecl.} =
  var n = CSize(0)

  while s[U64(n)] != '\0':
    inc n

  n
