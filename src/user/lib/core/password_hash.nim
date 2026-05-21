import ../net/crypto/crypto_types
import ../net/crypto/hkdf
import ./shadow
import ./strutils
import ./syscall


proc passwordLen(password: cstring): U32 =
  if password == nil:
    return U32(0)

  U32(cstrlen(password))


proc pbkdf2Sha256(password: cstring, salt: pointer, saltLen, iterations: U32, outHash: pointer): bool =
  if password == nil or salt == nil or outHash == nil or iterations == U32(0):
    return false

  var saltBlock: array[int(ShadowSaltLen + U32(4)), U8]
  var digestA: array[int(ShadowHashLen), U8]
  var digestB: array[int(ShadowHashLen), U8]

  zeroMem(addr saltBlock[0], U32(sizeof(saltBlock)))
  zeroMem(addr digestA[0], U32(sizeof(digestA)))
  zeroMem(addr digestB[0], U32(sizeof(digestB)))

  copyMem(addr saltBlock[0], salt, saltLen)
  saltBlock[saltLen] = U8(0)
  saltBlock[saltLen + U32(1)] = U8(0)
  saltBlock[saltLen + U32(2)] = U8(0)
  saltBlock[saltLen + U32(3)] = U8(1)

  let passLen = passwordLen(password)
  hmacSha256(cast[pointer](password), passLen, addr saltBlock[0], saltLen + U32(4), addr digestA[0])

  let outBytes = cast[ptr UncheckedArray[U8]](outHash)
  var i = U32(0)
  while i < ShadowHashLen:
    outBytes[i] = digestA[i]
    inc i

  var round = U32(1)
  while round < iterations:
    hmacSha256(cast[pointer](password), passLen, addr digestA[0], ShadowHashLen, addr digestB[0])

    i = U32(0)
    while i < ShadowHashLen:
      outBytes[i] = outBytes[i] xor digestB[i]
      digestA[i] = digestB[i]
      inc i

    inc round

  zeroMem(addr digestA[0], ShadowHashLen)
  zeroMem(addr digestB[0], ShadowHashLen)
  true


proc makePasswordHash*(name, password: cstring, entry: var ShadowEntry): bool =
  clearShadowEntry(entry)
  if name == nil or password == nil:
    return false

  if not copyCString(entry.name, name):
    return false

  entry.iterations = ShadowDefaultIterations
  if sysEntropy(addr entry.salt[0], U64(ShadowSaltLen)) != I32(ShadowSaltLen):
    return false

  pbkdf2Sha256(password, addr entry.salt[0], ShadowSaltLen, entry.iterations, addr entry.hash[0])


proc verifyPassword*(entry: ShadowEntry, password: cstring): bool =
  var computed: array[ShadowHashLen, U8]
  if not pbkdf2Sha256(password, unsafeAddr entry.salt[0], ShadowSaltLen, entry.iterations, addr computed[0]):
    return false

  let ok = secureEqual(addr computed[0], unsafeAddr entry.hash[0], ShadowHashLen)
  zeroMem(addr computed[0], ShadowHashLen)
  ok
