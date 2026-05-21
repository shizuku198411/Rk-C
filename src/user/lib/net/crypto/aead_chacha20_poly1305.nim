## Implements ChaCha20-Poly1305 AEAD encryption and decryption.
import ./chacha20
import ../../core/syscall
import ./crypto_types
import ./poly1305


## Performs Poly1305 update padded.
proc polyUpdatePadded(ctx: var Poly1305Ctx, data: pointer, len: U32) =
  var zeroPad: array[16, U8]
  if len > 0:
    poly1305Update(ctx, data, len)

  let rem = len mod 16
  if rem != 0:
    poly1305Update(ctx, addr zeroPad[0], 16 - rem)


## Performs Poly1305 aead tag.
proc polyAeadTag(key: pointer, nonce: pointer, aad: pointer, aadLen: U32,
                 ciphertext: pointer, ciphertextLen: U32, outTag: pointer) =
  var firstBlock: array[64, U8]
  var lengthBlock: array[16, U8]
  chacha20Block(key, 0, nonce, addr firstBlock[0])

  var ctx = Poly1305Ctx()
  poly1305Init(ctx, addr firstBlock[0])
  polyUpdatePadded(ctx, aad, aadLen)
  polyUpdatePadded(ctx, ciphertext, ciphertextLen)
  store64Le(addr lengthBlock[0], U64(aadLen))
  store64Le(addr lengthBlock[8], U64(ciphertextLen))
  poly1305Update(ctx, addr lengthBlock[0], 16)
  poly1305Final(ctx, outTag)


## Performs ChaCha20 chacha20 poly1305 encrypt.
proc chacha20Poly1305Encrypt*(key: pointer, nonce: pointer, aad: pointer, aadLen: U32,
                              plaintext: pointer, plaintextLen: U32,
                              ciphertext: pointer, tag: pointer): I32 =
  if key == nil or nonce == nil or ciphertext == nil or tag == nil:
    return -1
  if plaintextLen > 0 and plaintext == nil:
    return -1
  if aadLen > 0 and aad == nil:
    return -1

  chacha20Xor(key, 1, nonce, plaintext, ciphertext, plaintextLen)
  polyAeadTag(key, nonce, aad, aadLen, ciphertext, plaintextLen, tag)
  0


## Performs ChaCha20 chacha20 poly1305 decrypt.
proc chacha20Poly1305Decrypt*(key: pointer, nonce: pointer, aad: pointer, aadLen: U32,
                              ciphertext: pointer, ciphertextLen: U32,
                              tag: pointer, plaintext: pointer): I32 =
  if key == nil or nonce == nil or tag == nil or plaintext == nil:
    return -1
  if ciphertextLen > 0 and ciphertext == nil:
    return -1
  if aadLen > 0 and aad == nil:
    return -1

  var expected: array[Poly1305TagLen, U8]
  polyAeadTag(key, nonce, aad, aadLen, ciphertext, ciphertextLen, addr expected[0])
  if not secureEqual(addr expected[0], tag, U32(Poly1305TagLen)):
    return -1

  chacha20Xor(key, 1, nonce, ciphertext, plaintext, ciphertextLen)
  0
