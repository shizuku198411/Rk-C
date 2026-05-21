## Provides freestanding memory routines shared by kernel and userland.
import types


## Fills mem.
proc fillMem*(buf: pointer, value: U8, n: Size): pointer =
  let p = cast[ptr UncheckedArray[U8]](buf)
  var i = U64(0)
  while i < n:
    p[i] = value
    inc i
  buf


## Copies mem.
proc copyMem*(dest: pointer, src: pointer, n: Size): pointer =
  let d = cast[ptr UncheckedArray[U8]](dest)
  let s = cast[ptr UncheckedArray[U8]](src)
  var i = U64(0)
  while i < n:
    d[i] = s[i]
    inc i
  dest


## Implements the move mem helper.
proc moveMem*(dest: pointer, src: pointer, n: Size): pointer =
  let d = cast[ptr UncheckedArray[U8]](dest)
  let s = cast[ptr UncheckedArray[U8]](src)

  if dest == src or n == 0:
    return dest

  if cast[U64](dest) < cast[U64](src):
    var i = U64(0)
    while i < n:
      d[i] = s[i]
      inc i
  else:
    var i = n
    while i > 0:
      dec i
      d[i] = s[i]

  dest


## Implements the compare mem helper.
proc compareMem*(s1: pointer, s2: pointer, n: Size): cint =
  let a = cast[ptr UncheckedArray[U8]](s1)
  let b = cast[ptr UncheckedArray[U8]](s2)
  var i = U64(0)
  while i < n:
    if a[i] != b[i]:
      return cint(a[i]) - cint(b[i])
    inc i
  0


## Exports the C memset routine backed by fillMem.
proc memset*(s: pointer, c: cint, n: CSize): pointer {.exportc: "memset", cdecl.} =
  fillMem(s, U8(c and 0xff), Size(n))


## Exports the C memcpy routine backed by copyMem.
proc memcpy*(dest: pointer, src: pointer, n: CSize): pointer {.exportc: "memcpy", cdecl.} =
  copyMem(dest, src, Size(n))


## Exports the C memmove routine backed by moveMem.
proc memmove*(dest: pointer, src: pointer, n: CSize): pointer {.exportc: "memmove", cdecl.} =
  moveMem(dest, src, Size(n))


## Exports the C memcmp routine backed by compareMem.
proc memcmp*(s1: pointer, s2: pointer, n: CSize): cint {.exportc: "memcmp", cdecl.} =
  compareMem(s1, s2, Size(n))


## Zeroes mem.
proc zeroMem*(buf: pointer, n: Size) =
  discard fillMem(buf, 0'u8, n)


## Returns whether zeroed is true.
proc isZeroed*(buf: pointer, n: Size): bool =
  let p = cast[ptr UncheckedArray[U8]](buf)
  var i = U64(0)
  while i < n:
    if p[i] != 0'u8:
      return false
    inc i
  true
