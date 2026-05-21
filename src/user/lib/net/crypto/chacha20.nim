## Implements the ChaCha20 stream cipher.
import ./crypto_types
import ../../core/syscall

const ChachaConst: array[4, U32] = [
  0x61707865'u32, 0x3320646e'u32, 0x79622d32'u32, 0x6b206574'u32
]


## Rotates a 32-bit word left.
proc rotl(x: U32, n: int): U32 =
  (x shl n) or (x shr (32 - n))


## Runs one ChaCha20 quarter round.
proc quarterRound(a, b, c, d: var U32) =
  a = a + b
  d = rotl(d xor a, 16)
  c = c + d
  b = rotl(b xor c, 12)
  a = a + b
  d = rotl(d xor a, 8)
  c = c + d
  b = rotl(b xor c, 7)


## Performs ChaCha20 chacha20 block.
proc chacha20Block*(key: pointer, counter: U32, nonce: pointer, outBlock: pointer) =
  var state: array[16, U32]
  var working: array[16, U32]

  state[0] = ChachaConst[0]
  state[1] = ChachaConst[1]
  state[2] = ChachaConst[2]
  state[3] = ChachaConst[3]

  var i = 0
  while i < 8:
    state[4 + i] = load32Le(cast[pointer](cast[U64](key) + U64(i * 4)))
    inc i

  state[12] = counter
  state[13] = load32Le(nonce)
  state[14] = load32Le(cast[pointer](cast[U64](nonce) + 4))
  state[15] = load32Le(cast[pointer](cast[U64](nonce) + 8))

  i = 0
  while i < 16:
    working[i] = state[i]
    inc i

  i = 0
  while i < 10:
    quarterRound(working[0], working[4], working[8], working[12])
    quarterRound(working[1], working[5], working[9], working[13])
    quarterRound(working[2], working[6], working[10], working[14])
    quarterRound(working[3], working[7], working[11], working[15])
    quarterRound(working[0], working[5], working[10], working[15])
    quarterRound(working[1], working[6], working[11], working[12])
    quarterRound(working[2], working[7], working[8], working[13])
    quarterRound(working[3], working[4], working[9], working[14])
    inc i

  i = 0
  while i < 16:
    store32Le(cast[pointer](cast[U64](outBlock) + U64(i * 4)), working[i] + state[i])
    inc i


## Performs ChaCha20 chacha20 xor.
proc chacha20Xor*(key: pointer, counter: U32, nonce: pointer,
                  input: pointer, output: pointer, len: U32) =
  var streamBlock: array[64, U8]
  var blockCounter = counter
  var off = U32(0)
  let inBuf = cast[ptr UncheckedArray[U8]](input)
  let outBuf = cast[ptr UncheckedArray[U8]](output)

  while off < len:
    chacha20Block(key, blockCounter, nonce, addr streamBlock[0])
    inc blockCounter

    var take = U32(64)
    if len - off < take:
      take = len - off

    var i = U32(0)
    while i < take:
      outBuf[off + i] = inBuf[off + i] xor streamBlock[i]
      inc i

    off = off + take
