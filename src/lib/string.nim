## Provides freestanding C string routines required by generated code.
import types


## Compares two C strings using C strcmp semantics.
proc strcmp*(s1: cstring, s2: cstring): cint {.exportc: "strcmp", cdecl.} =
  var i = 0

  while s1[i] != '\0' and s1[i] == s2[i]:
    inc i

  cint(ord(s1[i])) - cint(ord(s2[i]))


## Returns the length of a C string.
proc strlen*(s: cstring): CSize {.exportc: "strlen", cdecl.} =
  var n = CSize(0)

  while s[U64(n)] != '\0':
    inc n

  n
