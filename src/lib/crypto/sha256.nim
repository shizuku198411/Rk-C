## Implements freestanding SHA-256 hashing shared by kernel and userland.
import ../types


const
  Sha256DigestLen* = 32
  Sha256BlockLen* = 64


type
  Sha256Ctx* = object
    state: array[8, U32]
    buffer: array[Sha256BlockLen, U8]
    bufferLen: U32
    totalLen: U64


const K: array[64, U32] = [
  0x428a2f98'u32, 0x71374491'u32, 0xb5c0fbcf'u32, 0xe9b5dba5'u32,
  0x3956c25b'u32, 0x59f111f1'u32, 0x923f82a4'u32, 0xab1c5ed5'u32,
  0xd807aa98'u32, 0x12835b01'u32, 0x243185be'u32, 0x550c7dc3'u32,
  0x72be5d74'u32, 0x80deb1fe'u32, 0x9bdc06a7'u32, 0xc19bf174'u32,
  0xe49b69c1'u32, 0xefbe4786'u32, 0x0fc19dc6'u32, 0x240ca1cc'u32,
  0x2de92c6f'u32, 0x4a7484aa'u32, 0x5cb0a9dc'u32, 0x76f988da'u32,
  0x983e5152'u32, 0xa831c66d'u32, 0xb00327c8'u32, 0xbf597fc7'u32,
  0xc6e00bf3'u32, 0xd5a79147'u32, 0x06ca6351'u32, 0x14292967'u32,
  0x27b70a85'u32, 0x2e1b2138'u32, 0x4d2c6dfc'u32, 0x53380d13'u32,
  0x650a7354'u32, 0x766a0abb'u32, 0x81c2c92e'u32, 0x92722c85'u32,
  0xa2bfe8a1'u32, 0xa81a664b'u32, 0xc24b8b70'u32, 0xc76c51a3'u32,
  0xd192e819'u32, 0xd6990624'u32, 0xf40e3585'u32, 0x106aa070'u32,
  0x19a4c116'u32, 0x1e376c08'u32, 0x2748774c'u32, 0x34b0bcb5'u32,
  0x391c0cb3'u32, 0x4ed8aa4a'u32, 0x5b9cca4f'u32, 0x682e6ff3'u32,
  0x748f82ee'u32, 0x78a5636f'u32, 0x84c87814'u32, 0x8cc70208'u32,
  0x90befffa'u32, 0xa4506ceb'u32, 0xbef9a3f7'u32, 0xc67178f2'u32
]


## Loads a big-endian 32-bit word.
proc load32Be(p: pointer): U32 =
  let b = cast[ptr UncheckedArray[U8]](p)
  (U32(b[0]) shl 24) or (U32(b[1]) shl 16) or (U32(b[2]) shl 8) or U32(b[3])


## Stores a big-endian 32-bit word.
proc store32Be(p: pointer, value: U32) =
  let b = cast[ptr UncheckedArray[U8]](p)
  b[0] = U8((value shr 24) and 0xff'u32)
  b[1] = U8((value shr 16) and 0xff'u32)
  b[2] = U8((value shr 8) and 0xff'u32)
  b[3] = U8(value and 0xff'u32)


## Stores a big-endian 64-bit word.
proc store64Be(p: pointer, value: U64) =
  let b = cast[ptr UncheckedArray[U8]](p)
  b[0] = U8((value shr 56) and 0xff'u64)
  b[1] = U8((value shr 48) and 0xff'u64)
  b[2] = U8((value shr 40) and 0xff'u64)
  b[3] = U8((value shr 32) and 0xff'u64)
  b[4] = U8((value shr 24) and 0xff'u64)
  b[5] = U8((value shr 16) and 0xff'u64)
  b[6] = U8((value shr 8) and 0xff'u64)
  b[7] = U8(value and 0xff'u64)


## Rotates a 32-bit word right.
proc rotr(x: U32, n: int): U32 =
  (x shr n) or (x shl (32 - n))


## Computes the SHA-256 choose function.
proc ch(x, y, z: U32): U32 =
  (x and y) xor ((not x) and z)


## Computes the SHA-256 majority function.
proc maj(x, y, z: U32): U32 =
  (x and y) xor (x and z) xor (y and z)


## Computes the SHA-256 uppercase sigma0 function.
proc bigSigma0(x: U32): U32 =
  rotr(x, 2) xor rotr(x, 13) xor rotr(x, 22)


## Computes the SHA-256 uppercase sigma1 function.
proc bigSigma1(x: U32): U32 =
  rotr(x, 6) xor rotr(x, 11) xor rotr(x, 25)


## Computes the SHA-256 lowercase sigma0 function.
proc smallSigma0(x: U32): U32 =
  rotr(x, 7) xor rotr(x, 18) xor (x shr 3)


## Computes the SHA-256 lowercase sigma1 function.
proc smallSigma1(x: U32): U32 =
  rotr(x, 17) xor rotr(x, 19) xor (x shr 10)


## Compresses one SHA-256 message block into the context.
proc compress(ctx: var Sha256Ctx, inputBlock: pointer) =
  var w: array[64, U32]
  var i = 0
  while i < 16:
    w[i] = load32Be(cast[pointer](cast[U64](inputBlock) + U64(i * 4)))
    inc i

  while i < 64:
    w[i] = smallSigma1(w[i - 2]) + w[i - 7] + smallSigma0(w[i - 15]) + w[i - 16]
    inc i

  var a = ctx.state[0]
  var b = ctx.state[1]
  var c = ctx.state[2]
  var d = ctx.state[3]
  var e = ctx.state[4]
  var f = ctx.state[5]
  var g = ctx.state[6]
  var h = ctx.state[7]

  i = 0
  while i < 64:
    let t1 = h + bigSigma1(e) + ch(e, f, g) + K[i] + w[i]
    let t2 = bigSigma0(a) + maj(a, b, c)
    h = g
    g = f
    f = e
    e = d + t1
    d = c
    c = b
    b = a
    a = t1 + t2
    inc i

  ctx.state[0] = ctx.state[0] + a
  ctx.state[1] = ctx.state[1] + b
  ctx.state[2] = ctx.state[2] + c
  ctx.state[3] = ctx.state[3] + d
  ctx.state[4] = ctx.state[4] + e
  ctx.state[5] = ctx.state[5] + f
  ctx.state[6] = ctx.state[6] + g
  ctx.state[7] = ctx.state[7] + h


## Initializes a SHA-256 context.
proc sha256Init*(ctx: var Sha256Ctx) =
  ctx.state[0] = 0x6a09e667'u32
  ctx.state[1] = 0xbb67ae85'u32
  ctx.state[2] = 0x3c6ef372'u32
  ctx.state[3] = 0xa54ff53a'u32
  ctx.state[4] = 0x510e527f'u32
  ctx.state[5] = 0x9b05688c'u32
  ctx.state[6] = 0x1f83d9ab'u32
  ctx.state[7] = 0x5be0cd19'u32
  ctx.bufferLen = U32(0)
  ctx.totalLen = U64(0)


## Adds bytes to a SHA-256 context.
proc sha256Update*(ctx: var Sha256Ctx, data: pointer, len: U32) =
  if data == nil or len == U32(0):
    return

  let input = cast[ptr UncheckedArray[U8]](data)
  var off = U32(0)
  ctx.totalLen = ctx.totalLen + U64(len)
  while off < len:
    let space = U32(Sha256BlockLen) - ctx.bufferLen
    var take = len - off
    if take > space:
      take = space

    var i = U32(0)
    while i < take:
      ctx.buffer[ctx.bufferLen + i] = input[off + i]
      inc i

    ctx.bufferLen = ctx.bufferLen + take
    off = off + take
    if ctx.bufferLen == U32(Sha256BlockLen):
      compress(ctx, addr ctx.buffer[0])
      ctx.bufferLen = U32(0)


## Finalizes a SHA-256 context into a 32-byte digest.
proc sha256Final*(ctx: var Sha256Ctx, outDigest: pointer) =
  if outDigest == nil:
    return

  let bitLen = ctx.totalLen * U64(8)
  ctx.buffer[ctx.bufferLen] = 0x80'u8
  inc ctx.bufferLen

  if ctx.bufferLen > U32(56):
    while ctx.bufferLen < U32(Sha256BlockLen):
      ctx.buffer[ctx.bufferLen] = 0
      inc ctx.bufferLen
    compress(ctx, addr ctx.buffer[0])
    ctx.bufferLen = U32(0)

  while ctx.bufferLen < U32(56):
    ctx.buffer[ctx.bufferLen] = 0
    inc ctx.bufferLen

  store64Be(addr ctx.buffer[56], bitLen)
  compress(ctx, addr ctx.buffer[0])

  var i = 0
  while i < 8:
    store32Be(cast[pointer](cast[U64](outDigest) + U64(i * 4)), ctx.state[i])
    inc i


## Hashes one contiguous buffer with SHA-256.
proc sha256*(data: pointer, len: U32, outDigest: pointer) =
  var ctx = Sha256Ctx()
  sha256Init(ctx)
  sha256Update(ctx, data, len)
  sha256Final(ctx, outDigest)
