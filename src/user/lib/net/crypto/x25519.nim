import ./crypto_types
import ../../core/syscall

const
  X25519KeyLen* = 32

type
  FieldElement = array[16, int64]

const
  FeOne: FieldElement = [int64(1), 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
  FeZero: FieldElement = [int64(0), 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
  Fe121665: FieldElement = [int64(0xdb41), 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]


proc car25519(o: var FieldElement) =
  var i = 0
  while i < 16:
    o[i] = o[i] + int64(1 shl 16)
    let c = o[i] shr 16
    if i < 15:
      o[i + 1] = o[i + 1] + c - 1
    else:
      o[0] = o[0] + int64(38) * (c - 1)
    o[i] = o[i] - (c shl 16)
    inc i


proc sel25519(p, q: var FieldElement, b: int64) =
  let c = not (b - 1)
  var i = 0
  while i < 16:
    let t = c and (p[i] xor q[i])
    p[i] = p[i] xor t
    q[i] = q[i] xor t
    inc i


proc unpack25519(o: var FieldElement, n: pointer) =
  let input = cast[ptr UncheckedArray[U8]](n)
  var i = 0
  while i < 16:
    o[i] = int64(input[2 * i]) + (int64(input[2 * i + 1]) shl 8)
    inc i

  o[15] = o[15] and int64(0x7fff)


proc pack25519(o: pointer, n: FieldElement) =
  var t = n
  var m: FieldElement
  var i = 0
  while i < 3:
    car25519(t)
    inc i

  var j = 0
  while j < 2:
    m[0] = t[0] - int64(0xffed)
    i = 1
    while i < 15:
      m[i] = t[i] - int64(0xffff) - ((m[i - 1] shr 16) and 1)
      m[i - 1] = m[i - 1] and int64(0xffff)
      inc i

    m[15] = t[15] - int64(0x7fff) - ((m[14] shr 16) and 1)
    let b = (m[15] shr 16) and 1
    m[14] = m[14] and int64(0xffff)
    sel25519(t, m, int64(1) - b)
    inc j

  let outBuf = cast[ptr UncheckedArray[U8]](o)
  i = 0
  while i < 16:
    outBuf[2 * i] = U8(t[i] and int64(0xff))
    outBuf[2 * i + 1] = U8((t[i] shr 8) and int64(0xff))
    inc i


proc addFe(o: var FieldElement, a, b: FieldElement) =
  var i = 0
  while i < 16:
    o[i] = a[i] + b[i]
    inc i


proc subFe(o: var FieldElement, a, b: FieldElement) =
  var i = 0
  while i < 16:
    o[i] = a[i] - b[i]
    inc i


proc mulFe(o: var FieldElement, a, b: FieldElement) =
  var t: array[31, int64]
  var i = 0
  while i < 16:
    var j = 0
    while j < 16:
      t[i + j] = t[i + j] + a[i] * b[j]
      inc j
    inc i

  i = 30
  while i >= 16:
    t[i - 16] = t[i - 16] + int64(38) * t[i]
    dec i

  i = 0
  while i < 16:
    o[i] = t[i]
    inc i

  car25519(o)
  car25519(o)


proc squareFe(o: var FieldElement, a: FieldElement) =
  mulFe(o, a, a)


proc inv25519(o: var FieldElement, i: FieldElement) =
  var c = i
  var a = 253
  while a >= 0:
    squareFe(c, c)
    if a != 2 and a != 4:
      mulFe(c, c, i)
    dec a

  o = c


proc clampScalar(dst: pointer, src: pointer) =
  copyMem(dst, src, U32(X25519KeyLen))
  let outBuf = cast[ptr UncheckedArray[U8]](dst)
  outBuf[0] = outBuf[0] and 248'u8
  outBuf[31] = (outBuf[31] and 127'u8) or 64'u8


proc x25519*(outShared: pointer, scalar: pointer, point: pointer): I32 =
  if outShared == nil or scalar == nil or point == nil:
    return -1

  var z: array[X25519KeyLen, U8]
  clampScalar(addr z[0], scalar)

  var x: FieldElement
  var a = FeOne
  var b: FieldElement
  var c = FeZero
  var d = FeOne
  var e: FieldElement
  var f: FieldElement
  unpack25519(x, point)
  b = x

  var i = 254
  while i >= 0:
    let r = int64((z[i shr 3] shr (i and 7)) and 1)
    sel25519(a, b, r)
    sel25519(c, d, r)
    addFe(e, a, c)
    subFe(a, a, c)
    addFe(c, b, d)
    subFe(b, b, d)
    squareFe(d, e)
    squareFe(f, a)
    mulFe(a, c, a)
    mulFe(c, b, e)
    addFe(e, a, c)
    subFe(a, a, c)
    squareFe(b, a)
    subFe(c, d, f)
    mulFe(a, c, Fe121665)
    addFe(a, a, d)
    mulFe(c, c, a)
    mulFe(a, d, f)
    mulFe(d, b, x)
    squareFe(b, e)
    sel25519(a, b, r)
    sel25519(c, d, r)
    dec i

  inv25519(c, c)
  mulFe(a, a, c)
  pack25519(outShared, a)
  0


proc x25519Base*(outPublic: pointer, scalar: pointer): I32 =
  var base: array[X25519KeyLen, U8]
  base[0] = 9
  x25519(outPublic, scalar, addr base[0])
