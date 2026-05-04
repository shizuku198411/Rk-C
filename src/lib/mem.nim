import types

proc memset*(buf: pointer, c: U8, n: Size): pointer =
  var p = cast[ptr UncheckedArray[U8]](buf)
  var i = U64(0)
  while i < n:
    p[i] = c
    inc i
  result = buf

proc zeroMem*(buf: pointer, n: Size) =
  discard memset(buf, 0'u8, n)

proc isZeroed*(buf: pointer, n: Size): bool =
  let p = cast[ptr UncheckedArray[U8]](buf)
  var i = U64(0)
  while i < n:
    if p[i] != 0'u8:
      return false
    inc i
  true
