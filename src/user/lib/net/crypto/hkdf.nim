import ./crypto_types
import ./sha256
import ../../core/syscall


proc hmacSha256*(key: pointer, keyLen: U32, data: pointer, dataLen: U32, outMac: pointer) =
  var keyBlock: array[Sha256BlockLen, U8]
  var innerPad: array[Sha256BlockLen, U8]
  var outerPad: array[Sha256BlockLen, U8]
  var keyHash: array[Sha256DigestLen, U8]

  if keyLen > U32(Sha256BlockLen):
    sha256(key, keyLen, addr keyHash[0])
    copyMem(addr keyBlock[0], addr keyHash[0], U32(Sha256DigestLen))
  else:
    copyMem(addr keyBlock[0], key, keyLen)

  var i = 0
  while i < Sha256BlockLen:
    innerPad[i] = keyBlock[i] xor 0x36'u8
    outerPad[i] = keyBlock[i] xor 0x5c'u8
    inc i

  var inner = Sha256Ctx()
  var innerDigest: array[Sha256DigestLen, U8]
  sha256Init(inner)
  sha256Update(inner, addr innerPad[0], U32(Sha256BlockLen))
  sha256Update(inner, data, dataLen)
  sha256Final(inner, addr innerDigest[0])

  var outer = Sha256Ctx()
  sha256Init(outer)
  sha256Update(outer, addr outerPad[0], U32(Sha256BlockLen))
  sha256Update(outer, addr innerDigest[0], U32(Sha256DigestLen))
  sha256Final(outer, outMac)


proc hkdfExtractSha256*(salt: pointer, saltLen: U32, ikm: pointer, ikmLen: U32, outPrk: pointer) =
  var zeroSalt: array[Sha256DigestLen, U8]
  if salt == nil or saltLen == 0:
    hmacSha256(addr zeroSalt[0], U32(Sha256DigestLen), ikm, ikmLen, outPrk)
  else:
    hmacSha256(salt, saltLen, ikm, ikmLen, outPrk)


proc hkdfExpandSha256*(prk: pointer, prkLen: U32, info: pointer,
                       infoLen: U32, outOkm: pointer, okmLen: U32): I32 =
  if prk == nil or outOkm == nil or okmLen == 0:
    return -1
  if okmLen > U32(255 * Sha256DigestLen):
    return -1

  var t: array[Sha256DigestLen, U8]
  var input: array[Sha256DigestLen + 256, U8]
  var produced = U32(0)
  var round = U8(1)
  var tLen = U32(0)
  let outBytes = cast[ptr UncheckedArray[U8]](outOkm)

  while produced < okmLen:
    copyMem(addr input[0], addr t[0], tLen)
    if info != nil and infoLen > 0:
      copyMem(addr input[tLen], info, infoLen)
    input[tLen + infoLen] = round

    hmacSha256(prk, prkLen, addr input[0], tLen + infoLen + 1, addr t[0])

    var take = U32(Sha256DigestLen)
    if okmLen - produced < take:
      take = okmLen - produced

    var i = U32(0)
    while i < take:
      outBytes[produced + i] = t[i]
      inc i

    produced = produced + take
    tLen = U32(Sha256DigestLen)
    inc round

  0


proc cstrlenLocal(s: cstring): U32 =
  if s == nil:
    return 0

  var n = U32(0)
  while s[n] != '\0':
    inc n

  n


proc hkdfExpandLabelSha256*(secret: pointer, label: cstring, context: pointer,
                            contextLen: U32, outOkm: pointer, okmLen: U32): I32 =
  if secret == nil or label == nil or outOkm == nil:
    return -1

  const Prefix = "tls13 "
  var info: array[256, U8]
  var pos = U32(0)
  let labelLen = cstrlenLocal(label)
  let fullLabelLen = U32(6) + labelLen
  if fullLabelLen > 255 or contextLen > 255:
    return -1

  info[pos] = U8((okmLen shr 8) and 0xff'u32)
  inc pos
  info[pos] = U8(okmLen and 0xff'u32)
  inc pos
  info[pos] = U8(fullLabelLen)
  inc pos

  var i = U32(0)
  while i < 6:
    info[pos] = U8(Prefix[i])
    inc pos
    inc i

  i = U32(0)
  while i < labelLen:
    info[pos] = U8(label[i])
    inc pos
    inc i

  info[pos] = U8(contextLen)
  inc pos
  if contextLen > 0:
    copyMem(addr info[pos], context, contextLen)
    pos = pos + contextLen

  hkdfExpandSha256(secret, U32(Sha256DigestLen), addr info[0], pos, outOkm, okmLen)
