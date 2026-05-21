## Provides low-level byte and endian helpers for crypto code.
import ../../core/syscall

const
  Sha256DigestLen* = 32
  Sha256BlockLen* = 64
  Chacha20KeyLen* = 32
  Chacha20NonceLen* = 12
  Poly1305KeyLen* = 32
  Poly1305TagLen* = 16

type
  ByteSeq32* = array[32, U8]
  ByteSeq64* = array[64, U8]


## Zeroes mem.
proc zeroMem*(buf: pointer, len: U32) =
  if buf == nil:
    return

  let outBuf = cast[ptr UncheckedArray[U8]](buf)
  var i = U32(0)
  while i < len:
    outBuf[i] = 0
    inc i


## Copies mem.
proc copyMem*(dst, src: pointer, len: U32) =
  if dst == nil or src == nil:
    return

  let d = cast[ptr UncheckedArray[U8]](dst)
  let s = cast[ptr UncheckedArray[U8]](src)
  var i = U32(0)
  while i < len:
    d[i] = s[i]
    inc i


## Loads load32 le.
proc load32Le*(p: pointer): U32 =
  let b = cast[ptr UncheckedArray[U8]](p)
  U32(b[0]) or (U32(b[1]) shl 8) or (U32(b[2]) shl 16) or (U32(b[3]) shl 24)


## Stores store32 le.
proc store32Le*(p: pointer, value: U32) =
  let b = cast[ptr UncheckedArray[U8]](p)
  b[0] = U8(value and 0xff'u32)
  b[1] = U8((value shr 8) and 0xff'u32)
  b[2] = U8((value shr 16) and 0xff'u32)
  b[3] = U8((value shr 24) and 0xff'u32)


## Stores store64 le.
proc store64Le*(p: pointer, value: U64) =
  let b = cast[ptr UncheckedArray[U8]](p)
  b[0] = U8(value and 0xff'u64)
  b[1] = U8((value shr 8) and 0xff'u64)
  b[2] = U8((value shr 16) and 0xff'u64)
  b[3] = U8((value shr 24) and 0xff'u64)
  b[4] = U8((value shr 32) and 0xff'u64)
  b[5] = U8((value shr 40) and 0xff'u64)
  b[6] = U8((value shr 48) and 0xff'u64)
  b[7] = U8((value shr 56) and 0xff'u64)


## Loads load32 be.
proc load32Be*(p: pointer): U32 =
  let b = cast[ptr UncheckedArray[U8]](p)
  (U32(b[0]) shl 24) or (U32(b[1]) shl 16) or (U32(b[2]) shl 8) or U32(b[3])


## Stores store32 be.
proc store32Be*(p: pointer, value: U32) =
  let b = cast[ptr UncheckedArray[U8]](p)
  b[0] = U8((value shr 24) and 0xff'u32)
  b[1] = U8((value shr 16) and 0xff'u32)
  b[2] = U8((value shr 8) and 0xff'u32)
  b[3] = U8(value and 0xff'u32)


## Stores store64 be.
proc store64Be*(p: pointer, value: U64) =
  let b = cast[ptr UncheckedArray[U8]](p)
  b[0] = U8((value shr 56) and 0xff'u64)
  b[1] = U8((value shr 48) and 0xff'u64)
  b[2] = U8((value shr 40) and 0xff'u64)
  b[3] = U8((value shr 32) and 0xff'u64)
  b[4] = U8((value shr 24) and 0xff'u64)
  b[5] = U8((value shr 16) and 0xff'u64)
  b[6] = U8((value shr 8) and 0xff'u64)
  b[7] = U8(value and 0xff'u64)


## Implements the xor bytes helper.
proc xorBytes*(dst, a, b: pointer, len: U32) =
  let outBuf = cast[ptr UncheckedArray[U8]](dst)
  let left = cast[ptr UncheckedArray[U8]](a)
  let right = cast[ptr UncheckedArray[U8]](b)
  var i = U32(0)
  while i < len:
    outBuf[i] = left[i] xor right[i]
    inc i


## Implements the secure equal helper.
proc secureEqual*(a, b: pointer, len: U32): bool =
  if a == nil or b == nil:
    return false

  let left = cast[ptr UncheckedArray[U8]](a)
  let right = cast[ptr UncheckedArray[U8]](b)
  var diff = U8(0)
  var i = U32(0)
  while i < len:
    diff = diff or (left[i] xor right[i])
    inc i

  diff == 0
