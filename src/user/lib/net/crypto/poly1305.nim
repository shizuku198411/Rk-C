import ./crypto_types
import ../../core/syscall

type
  Poly1305Ctx* = object
    r: array[5, U64]
    h: array[5, U64]
    pad: array[4, U32]
    buffer: array[16, U8]
    bufferLen: U32
    finished: bool

const Mask26 = U64(0x3ffffff)


proc loadKeyWord(key: pointer, off: U64): U32 =
  load32Le(cast[pointer](cast[U64](key) + off))


proc blocks(ctx: var Poly1305Ctx, data: pointer, len: U32, hibit: U64) =
  let input = cast[ptr UncheckedArray[U8]](data)
  var off = U32(0)
  let r0 = ctx.r[0]
  let r1 = ctx.r[1]
  let r2 = ctx.r[2]
  let r3 = ctx.r[3]
  let r4 = ctx.r[4]
  let s1 = r1 * 5
  let s2 = r2 * 5
  let s3 = r3 * 5
  let s4 = r4 * 5

  while off + 16 <= len:
    let ptr0 = cast[pointer](cast[U64](data) + U64(off))
    let t0 = U64(load32Le(ptr0))
    let t1 = U64(load32Le(cast[pointer](cast[U64](ptr0) + 4)))
    let t2 = U64(load32Le(cast[pointer](cast[U64](ptr0) + 8)))
    let t3 = U64(load32Le(cast[pointer](cast[U64](ptr0) + 12)))

    ctx.h[0] = ctx.h[0] + (t0 and Mask26)
    ctx.h[1] = ctx.h[1] + (((t0 shr 26) or (t1 shl 6)) and Mask26)
    ctx.h[2] = ctx.h[2] + (((t1 shr 20) or (t2 shl 12)) and Mask26)
    ctx.h[3] = ctx.h[3] + (((t2 shr 14) or (t3 shl 18)) and Mask26)
    ctx.h[4] = ctx.h[4] + ((t3 shr 8) or hibit)

    let d0 = ctx.h[0] * r0 + ctx.h[1] * s4 + ctx.h[2] * s3 + ctx.h[3] * s2 + ctx.h[4] * s1
    var d1 = ctx.h[0] * r1 + ctx.h[1] * r0 + ctx.h[2] * s4 + ctx.h[3] * s3 + ctx.h[4] * s2
    var d2 = ctx.h[0] * r2 + ctx.h[1] * r1 + ctx.h[2] * r0 + ctx.h[3] * s4 + ctx.h[4] * s3
    var d3 = ctx.h[0] * r3 + ctx.h[1] * r2 + ctx.h[2] * r1 + ctx.h[3] * r0 + ctx.h[4] * s4
    var d4 = ctx.h[0] * r4 + ctx.h[1] * r3 + ctx.h[2] * r2 + ctx.h[3] * r1 + ctx.h[4] * r0

    var c = d0 shr 26
    ctx.h[0] = d0 and Mask26
    d1 = d1 + c
    c = d1 shr 26
    ctx.h[1] = d1 and Mask26
    d2 = d2 + c
    c = d2 shr 26
    ctx.h[2] = d2 and Mask26
    d3 = d3 + c
    c = d3 shr 26
    ctx.h[3] = d3 and Mask26
    d4 = d4 + c
    c = d4 shr 26
    ctx.h[4] = d4 and Mask26
    ctx.h[0] = ctx.h[0] + c * 5
    c = ctx.h[0] shr 26
    ctx.h[0] = ctx.h[0] and Mask26
    ctx.h[1] = ctx.h[1] + c

    off = off + 16

  discard input


proc poly1305Init*(ctx: var Poly1305Ctx, key: pointer) =
  let t0 = U64(loadKeyWord(key, 0))
  let t1 = U64(loadKeyWord(key, 4))
  let t2 = U64(loadKeyWord(key, 8))
  let t3 = U64(loadKeyWord(key, 12))

  ctx.r[0] = t0 and Mask26
  ctx.r[1] = ((t0 shr 26) or (t1 shl 6)) and U64(0x3ffff03)
  ctx.r[2] = ((t1 shr 20) or (t2 shl 12)) and U64(0x3ffc0ff)
  ctx.r[3] = ((t2 shr 14) or (t3 shl 18)) and U64(0x3f03fff)
  ctx.r[4] = (t3 shr 8) and U64(0x00fffff)

  var i = 0
  while i < 5:
    ctx.h[i] = 0
    inc i

  i = 0
  while i < 4:
    ctx.pad[i] = loadKeyWord(key, U64(16 + i * 4))
    inc i

  ctx.bufferLen = 0
  ctx.finished = false


proc poly1305Update*(ctx: var Poly1305Ctx, data: pointer, len: U32) =
  if data == nil or len == 0 or ctx.finished:
    return

  let input = cast[ptr UncheckedArray[U8]](data)
  var off = U32(0)
  if ctx.bufferLen > 0:
    var want = U32(16) - ctx.bufferLen
    if want > len:
      want = len

    var i = U32(0)
    while i < want:
      ctx.buffer[ctx.bufferLen + i] = input[i]
      inc i

    ctx.bufferLen = ctx.bufferLen + want
    off = off + want
    if ctx.bufferLen < 16:
      return

    blocks(ctx, addr ctx.buffer[0], 16, U64(1 shl 24))
    ctx.bufferLen = 0

  let fullLen = ((len - off) div 16) * 16
  if fullLen > 0:
    blocks(ctx, cast[pointer](cast[U64](data) + U64(off)), fullLen, U64(1 shl 24))
    off = off + fullLen

  while off < len:
    ctx.buffer[ctx.bufferLen] = input[off]
    inc ctx.bufferLen
    inc off


proc poly1305Final*(ctx: var Poly1305Ctx, outTag: pointer) =
  if outTag == nil or ctx.finished:
    return

  if ctx.bufferLen > 0:
    ctx.buffer[ctx.bufferLen] = 1
    inc ctx.bufferLen
    while ctx.bufferLen < 16:
      ctx.buffer[ctx.bufferLen] = 0
      inc ctx.bufferLen

    blocks(ctx, addr ctx.buffer[0], 16, 0)

  var c = ctx.h[1] shr 26
  ctx.h[1] = ctx.h[1] and Mask26
  ctx.h[2] = ctx.h[2] + c
  c = ctx.h[2] shr 26
  ctx.h[2] = ctx.h[2] and Mask26
  ctx.h[3] = ctx.h[3] + c
  c = ctx.h[3] shr 26
  ctx.h[3] = ctx.h[3] and Mask26
  ctx.h[4] = ctx.h[4] + c
  c = ctx.h[4] shr 26
  ctx.h[4] = ctx.h[4] and Mask26
  ctx.h[0] = ctx.h[0] + c * 5
  c = ctx.h[0] shr 26
  ctx.h[0] = ctx.h[0] and Mask26
  ctx.h[1] = ctx.h[1] + c

  var g0 = ctx.h[0] + 5
  c = g0 shr 26
  g0 = g0 and Mask26
  var g1 = ctx.h[1] + c
  c = g1 shr 26
  g1 = g1 and Mask26
  var g2 = ctx.h[2] + c
  c = g2 shr 26
  g2 = g2 and Mask26
  var g3 = ctx.h[3] + c
  c = g3 shr 26
  g3 = g3 and Mask26
  var g4 = ctx.h[4] + c - U64(1 shl 26)

  var mask = (g4 shr 63) - 1
  g0 = g0 and mask
  g1 = g1 and mask
  g2 = g2 and mask
  g3 = g3 and mask
  g4 = g4 and mask
  mask = not mask
  ctx.h[0] = (ctx.h[0] and mask) or g0
  ctx.h[1] = (ctx.h[1] and mask) or g1
  ctx.h[2] = (ctx.h[2] and mask) or g2
  ctx.h[3] = (ctx.h[3] and mask) or g3
  ctx.h[4] = (ctx.h[4] and mask) or g4

  var f0 = (ctx.h[0] or (ctx.h[1] shl 26)) and U64(0xffffffff'u32)
  var f1 = ((ctx.h[1] shr 6) or (ctx.h[2] shl 20)) and U64(0xffffffff'u32)
  var f2 = ((ctx.h[2] shr 12) or (ctx.h[3] shl 14)) and U64(0xffffffff'u32)
  var f3 = ((ctx.h[3] shr 18) or (ctx.h[4] shl 8)) and U64(0xffffffff'u32)

  f0 = f0 + U64(ctx.pad[0])
  f1 = f1 + U64(ctx.pad[1]) + (f0 shr 32)
  f0 = f0 and U64(0xffffffff'u32)
  f2 = f2 + U64(ctx.pad[2]) + (f1 shr 32)
  f1 = f1 and U64(0xffffffff'u32)
  f3 = f3 + U64(ctx.pad[3]) + (f2 shr 32)
  f2 = f2 and U64(0xffffffff'u32)

  store32Le(outTag, U32(f0))
  store32Le(cast[pointer](cast[U64](outTag) + 4), U32(f1))
  store32Le(cast[pointer](cast[U64](outTag) + 8), U32(f2))
  store32Le(cast[pointer](cast[U64](outTag) + 12), U32(f3))
  ctx.finished = true


proc poly1305Mac*(key: pointer, data: pointer, len: U32, outTag: pointer) =
  var ctx = Poly1305Ctx()
  poly1305Init(ctx, key)
  poly1305Update(ctx, data, len)
  poly1305Final(ctx, outTag)
