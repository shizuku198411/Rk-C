import types

type
  CSize* {.importc: "size_t", header: "<string.h>".} = uint

proc memset*(s: pointer, c: cint, n: CSize): pointer {.exportc: "memset", cdecl.} =
  let p = cast[ptr UncheckedArray[U8]](s)
  let value = U8(c and 0xff)
  var i = CSize(0)

  while i < n:
    p[U64(i)] = value
    inc i

  s

proc memcpy*(dest: pointer, src: pointer, n: CSize): pointer {.exportc: "memcpy", cdecl.} =
  let d = cast[ptr UncheckedArray[U8]](dest)
  let s = cast[ptr UncheckedArray[U8]](src)
  var i = CSize(0)

  while i < n:
    d[U64(i)] = s[U64(i)]
    inc i

  dest

proc memmove*(dest: pointer, src: pointer, n: CSize): pointer {.exportc: "memmove", cdecl.} =
  let d = cast[ptr UncheckedArray[U8]](dest)
  let s = cast[ptr UncheckedArray[U8]](src)

  if dest == src or n == 0:
    return dest

  if cast[U64](dest) < cast[U64](src):
    var i = CSize(0)
    while i < n:
      d[U64(i)] = s[U64(i)]
      inc i
  else:
    var i = n
    while i > 0:
      dec i
      d[U64(i)] = s[U64(i)]

  dest

proc memcmp*(s1: pointer, s2: pointer, n: CSize): cint {.exportc: "memcmp", cdecl.} =
  let a = cast[ptr UncheckedArray[U8]](s1)
  let b = cast[ptr UncheckedArray[U8]](s2)
  var i = CSize(0)

  while i < n:
    if a[U64(i)] != b[U64(i)]:
      return cint(a[U64(i)]) - cint(b[U64(i)])
    inc i

  0

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
