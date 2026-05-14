import ./net_tcp
import ./crypto/aead_chacha20_poly1305
import ./crypto/chacha20
import ./crypto/crypto_types
import ./crypto/hkdf
import ./crypto/sha256
import ./crypto/x25519
import ../core/syscall

const
  TlsDefaultPort* = U16(443)
  TlsErrUnsupported* = I32(-2)
  TlsErrBadServerHello* = I32(-3)

  TlsRecordChangeCipherSpec = U8(20)
  TlsRecordAlert = U8(21)
  TlsRecordHandshake = U8(22)
  TlsRecordApplicationData = U8(23)

  TlsHandshakeClientHello = U8(1)
  TlsHandshakeServerHello = U8(2)
  TlsHandshakeFinished = U8(20)

  TlsCipherChacha20Poly1305Sha256 = U16(0x1303)
  TlsGroupX25519 = U16(0x001d)
  TlsVersion13 = U16(0x0304)

  TlsMaxRecord = 17408
  TlsMaxRaw = 24576
  TlsSlotCount = 2
  TlsHandleBase = I32(100000)

type
  TlsClient* = object
    handle*: I32
    lastError*: I32
    active: bool
    privateKey: array[32, U8]
    publicKey: array[32, U8]
    serverPublicKey: array[32, U8]
    sharedSecret: array[32, U8]
    handshakeSecret: array[32, U8]
    clientHandshakeSecret: array[32, U8]
    serverHandshakeSecret: array[32, U8]
    clientAppSecret: array[32, U8]
    serverAppSecret: array[32, U8]
    clientHandshakeKey: array[32, U8]
    serverHandshakeKey: array[32, U8]
    clientAppKey: array[32, U8]
    serverAppKey: array[32, U8]
    clientHandshakeIv: array[12, U8]
    serverHandshakeIv: array[12, U8]
    clientAppIv: array[12, U8]
    serverAppIv: array[12, U8]
    clientHandshakeSeq: U64
    serverHandshakeSeq: U64
    clientAppSeq: U64
    serverAppSeq: U64
    rawOff: U32
    rawLen: U32
    appOff: U32
    appLen: U32
    transcript: Sha256Ctx

var
  tlsSlots: array[TlsSlotCount, TlsClient]
  txBuf: array[TlsMaxRecord, U8]
  rxBuf: array[TlsMaxRecord, U8]
  rawBuf: array[TlsMaxRaw, U8]
  plainBuf: array[TlsMaxRecord, U8]
  cipherBuf: array[TlsMaxRecord, U8]
  appBuf: array[TlsMaxRecord, U8]
  rngCounter: U64
  tlsLastError: I32


proc tlsErrorName*(code: I32): cstring =
  case code
  of 0:
    cstring("ok")
  of TlsErrUnsupported:
    cstring("unsupported TLS feature")
  of TlsErrBadServerHello:
    cstring("invalid ServerHello")
  else:
    cstring("unknown TLS error")


proc tlsLastErrorName*(): cstring =
  tlsErrorName(tlsLastError)


proc tlsCryptoReady*(): bool =
  var zeroKey: array[32, U8]
  var zeroNonce: array[12, U8]
  var outBlock: array[64, U8]
  var prk: array[32, U8]
  var publicKey: array[32, U8]

  chacha20Block(addr zeroKey[0], U32(0), addr zeroNonce[0], addr outBlock[0])
  hkdfExtractSha256(nil, 0, addr zeroKey[0], U32(32), addr prk[0])
  discard x25519Base(addr publicKey[0], addr zeroKey[0])
  discard chacha20Poly1305Encrypt(nil, nil, nil, 0, nil, 0, nil, nil)
  true


proc put8(buf: var array[TlsMaxRecord, U8], pos: var U32, value: U8): bool =
  if pos >= U32(TlsMaxRecord):
    return false

  buf[pos] = value
  inc pos
  true


proc put16(buf: var array[TlsMaxRecord, U8], pos: var U32, value: U16): bool =
  if pos + 2 > U32(TlsMaxRecord):
    return false

  buf[pos] = U8((value shr 8) and 0xff'u16)
  buf[pos + 1] = U8(value and 0xff'u16)
  pos = pos + 2
  true


proc put24(buf: var array[TlsMaxRecord, U8], pos: var U32, value: U32): bool =
  if pos + 3 > U32(TlsMaxRecord):
    return false

  buf[pos] = U8((value shr 16) and 0xff'u32)
  buf[pos + 1] = U8((value shr 8) and 0xff'u32)
  buf[pos + 2] = U8(value and 0xff'u32)
  pos = pos + 3
  true


proc patch16(buf: var array[TlsMaxRecord, U8], pos: U32, value: U16) =
  buf[pos] = U8((value shr 8) and 0xff'u16)
  buf[pos + 1] = U8(value and 0xff'u16)


proc patch24(buf: var array[TlsMaxRecord, U8], pos: U32, value: U32) =
  buf[pos] = U8((value shr 16) and 0xff'u32)
  buf[pos + 1] = U8((value shr 8) and 0xff'u32)
  buf[pos + 2] = U8(value and 0xff'u32)


proc copyBytes(buf: var array[TlsMaxRecord, U8], pos: var U32, data: pointer, len: U32): bool =
  if pos + len > U32(TlsMaxRecord):
    return false

  copyMem(addr buf[pos], data, len)
  pos = pos + len
  true


proc get16(data: ptr UncheckedArray[U8], pos: U32): U16 =
  (U16(data[pos]) shl 8) or U16(data[pos + 1])


proc get24(data: ptr UncheckedArray[U8], pos: U32): U32 =
  (U32(data[pos]) shl 16) or (U32(data[pos + 1]) shl 8) or U32(data[pos + 2])


proc cstrlenLocal(s: cstring): U32 =
  if s == nil:
    return 0

  var n = U32(0)
  while s[n] != '\0':
    inc n

  n


proc fillPseudoRandom(buf: pointer, len: U32) =
  let outBuf = cast[ptr UncheckedArray[U8]](buf)
  inc rngCounter
  var x = sysTicks() xor (U64(sysGetPid()) shl 32) xor
          (rngCounter * U64(0x9e3779b97f4a7c15'u64))
  var i = U32(0)
  while i < len:
    x = x xor (x shl 13)
    x = x xor (x shr 7)
    x = x xor (x shl 17)
    outBuf[i] = U8((x shr ((i and 7) * 8)) and 0xff'u64)
    inc i


proc fillRandom(buf: pointer, len: U32) =
  if sysEntropy(buf, U64(len)) == I32(len):
    return

  fillPseudoRandom(buf, len)


proc makeKeyPair(client: var TlsClient) =
  fillRandom(addr client.privateKey[0], U32(32))
  discard x25519Base(addr client.publicKey[0], addr client.privateKey[0])


proc writeServerName(host: cstring, pos: var U32): bool =
  let hostLen = cstrlenLocal(host)
  if hostLen == 0 or hostLen > 255:
    return false

  let extStart = pos
  if not put16(txBuf, pos, U16(0)):
    return false
  if not put16(txBuf, pos, U16(0)):
    return false

  let bodyStart = pos
  if not put16(txBuf, pos, U16(hostLen + 3)):
    return false
  if not put8(txBuf, pos, U8(0)):
    return false
  if not put16(txBuf, pos, U16(hostLen)):
    return false
  if not copyBytes(txBuf, pos, cast[pointer](host), hostLen):
    return false

  patch16(txBuf, extStart + 2, U16(pos - bodyStart))
  true


proc buildClientHello(client: var TlsClient, host: cstring, outLen: var U32): bool =
  var pos = U32(0)
  var randomBytes: array[32, U8]
  var sessionId: array[32, U8]
  fillRandom(addr randomBytes[0], U32(32))
  fillRandom(addr sessionId[0], U32(32))

  if not put8(txBuf, pos, TlsHandshakeClientHello):
    return false
  let handshakeLenPos = pos
  if not put24(txBuf, pos, 0):
    return false

  if not put16(txBuf, pos, U16(0x0303)):
    return false
  if not copyBytes(txBuf, pos, addr randomBytes[0], U32(32)):
    return false
  if not put8(txBuf, pos, U8(32)):
    return false
  if not copyBytes(txBuf, pos, addr sessionId[0], U32(32)):
    return false
  if not put16(txBuf, pos, U16(2)):
    return false
  if not put16(txBuf, pos, TlsCipherChacha20Poly1305Sha256):
    return false
  if not put8(txBuf, pos, U8(1)):
    return false
  if not put8(txBuf, pos, U8(0)):
    return false

  let extLenPos = pos
  if not put16(txBuf, pos, 0):
    return false
  let extStart = pos

  if not writeServerName(host, pos):
    return false

  if not put16(txBuf, pos, U16(43)):
    return false
  if not put16(txBuf, pos, U16(3)):
    return false
  if not put8(txBuf, pos, U8(2)):
    return false
  if not put16(txBuf, pos, TlsVersion13):
    return false

  if not put16(txBuf, pos, U16(10)):
    return false
  if not put16(txBuf, pos, U16(4)):
    return false
  if not put16(txBuf, pos, U16(2)):
    return false
  if not put16(txBuf, pos, TlsGroupX25519):
    return false

  if not put16(txBuf, pos, U16(13)):
    return false
  if not put16(txBuf, pos, U16(8)):
    return false
  if not put16(txBuf, pos, U16(6)):
    return false
  if not put16(txBuf, pos, U16(0x0403)):
    return false
  if not put16(txBuf, pos, U16(0x0804)):
    return false
  if not put16(txBuf, pos, U16(0x0807)):
    return false

  if not put16(txBuf, pos, U16(51)):
    return false
  if not put16(txBuf, pos, U16(38)):
    return false
  if not put16(txBuf, pos, U16(36)):
    return false
  if not put16(txBuf, pos, TlsGroupX25519):
    return false
  if not put16(txBuf, pos, U16(32)):
    return false
  if not copyBytes(txBuf, pos, addr client.publicKey[0], U32(32)):
    return false

  patch16(txBuf, extLenPos, U16(pos - extStart))
  patch24(txBuf, handshakeLenPos, pos - 4)
  outLen = pos
  true


proc sendPlainRecord(handle: I32, contentType: U8, data: pointer, len: U32): I32 =
  if len + 5 > U32(TlsMaxRecord):
    return -1

  cipherBuf[0] = contentType
  cipherBuf[1] = 0x03'u8
  cipherBuf[2] = 0x03'u8
  cipherBuf[3] = U8((len shr 8) and 0xff'u32)
  cipherBuf[4] = U8(len and 0xff'u32)
  copyMem(addr cipherBuf[5], data, len)

  tcpSend(handle, addr cipherBuf[0], len + 5)


proc compactRaw(client: var TlsClient) =
  if client.rawOff == 0:
    return

  var i = U32(0)
  while i < client.rawLen:
    rawBuf[i] = rawBuf[client.rawOff + i]
    inc i

  client.rawOff = 0


proc fillRaw(client: var TlsClient, need: U32): bool =
  while client.rawLen < need:
    compactRaw(client)
    if client.rawLen >= U32(TlsMaxRaw):
      return false

    let n = tcpReceive(client.handle, addr rawBuf[client.rawLen], U32(TlsMaxRaw) - client.rawLen)
    if n <= 0:
      return false

    client.rawLen = client.rawLen + U32(n)

  true


proc readRaw(client: var TlsClient, outData: pointer, len: U32): bool =
  if not fillRaw(client, len):
    return false

  copyMem(outData, addr rawBuf[client.rawOff], len)
  client.rawOff = client.rawOff + len
  client.rawLen = client.rawLen - len
  if client.rawLen == 0:
    client.rawOff = 0

  true


proc receiveRecord(client: var TlsClient, outContentType: var U8,
                   outData: pointer, capacity: U32): I32 =
  var header: array[5, U8]
  if not readRaw(client, addr header[0], U32(5)):
    return -1

  outContentType = header[0]
  let recordLen = (U32(header[3]) shl 8) or U32(header[4])
  if recordLen > capacity or recordLen > U32(TlsMaxRecord):
    return -1
  if not readRaw(client, outData, recordLen):
    return -1

  I32(recordLen)


proc parseServerHello(client: var TlsClient, data: pointer, len: U32): bool =
  if len < 42:
    return false

  let input = cast[ptr UncheckedArray[U8]](data)
  if input[0] != TlsHandshakeServerHello:
    return false

  let msgLen = get24(input, 1)
  if msgLen + 4 > len:
    return false

  if get16(input, 4) != U16(0x0303):
    return false

  var pos = U32(38)
  if pos >= len:
    return false
  let sessionLen = U32(input[pos])
  inc pos
  if pos + sessionLen + 3 > len:
    return false
  pos = pos + sessionLen

  let cipher = get16(input, pos)
  pos = pos + 2
  if cipher != TlsCipherChacha20Poly1305Sha256:
    return false
  if input[pos] != 0:
    return false
  inc pos

  if pos + 2 > len:
    return false
  let extLen = U32(get16(input, pos))
  pos = pos + 2
  if pos + extLen > len:
    return false

  let endPos = pos + extLen
  var sawVersion = false
  var sawKeyShare = false
  while pos + 4 <= endPos:
    let extType = get16(input, pos)
    let extDataLen = U32(get16(input, pos + 2))
    pos = pos + 4
    if pos + extDataLen > endPos:
      return false

    if extType == U16(43):
      if extDataLen != 2 or get16(input, pos) != TlsVersion13:
        return false
      sawVersion = true
    elif extType == U16(51):
      if extDataLen != 36:
        return false
      if get16(input, pos) != TlsGroupX25519:
        return false
      if get16(input, pos + 2) != U16(32):
        return false
      copyMem(addr client.serverPublicKey[0], cast[pointer](cast[U64](data) + U64(pos + 4)), U32(32))
      sawKeyShare = true

    pos = pos + extDataLen

  sawVersion and sawKeyShare


proc trafficKey(secret, outKey, outIv: pointer) =
  discard hkdfExpandLabelSha256(secret, "key", nil, U32(0), outKey, U32(32))
  discard hkdfExpandLabelSha256(secret, "iv", nil, U32(0), outIv, U32(12))


proc deriveHandshakeSecrets(client: var TlsClient) =
  var zeros: array[32, U8]
  var emptyHash: array[32, U8]
  var earlySecret: array[32, U8]
  var derivedSecret: array[32, U8]
  var transcriptHash: array[32, U8]
  var emptyCtx = Sha256Ctx()

  sha256Init(emptyCtx)
  sha256Final(emptyCtx, addr emptyHash[0])
  hkdfExtractSha256(addr zeros[0], U32(32), addr zeros[0], U32(32), addr earlySecret[0])
  discard hkdfExpandLabelSha256(addr earlySecret[0], "derived", addr emptyHash[0],
                                U32(32), addr derivedSecret[0], U32(32))
  hkdfExtractSha256(addr derivedSecret[0], U32(32), addr client.sharedSecret[0],
                    U32(32), addr client.handshakeSecret[0])

  var transcriptCopy = client.transcript
  sha256Final(transcriptCopy, addr transcriptHash[0])
  discard hkdfExpandLabelSha256(addr client.handshakeSecret[0], "c hs traffic",
                                addr transcriptHash[0], U32(32),
                                addr client.clientHandshakeSecret[0], U32(32))
  discard hkdfExpandLabelSha256(addr client.handshakeSecret[0], "s hs traffic",
                                addr transcriptHash[0], U32(32),
                                addr client.serverHandshakeSecret[0], U32(32))
  trafficKey(addr client.clientHandshakeSecret[0], addr client.clientHandshakeKey[0],
             addr client.clientHandshakeIv[0])
  trafficKey(addr client.serverHandshakeSecret[0], addr client.serverHandshakeKey[0],
             addr client.serverHandshakeIv[0])


proc makeNonce(iv: pointer, seq: U64, outNonce: pointer) =
  copyMem(outNonce, iv, U32(12))
  let nonce = cast[ptr UncheckedArray[U8]](outNonce)
  var i = 0
  while i < 8:
    nonce[4 + i] = nonce[4 + i] xor U8((seq shr U64((7 - i) * 8)) and 0xff'u64)
    inc i


proc decryptRecord(key, iv: pointer, seq: var U64, outerType: U8,
                   encrypted: pointer, encryptedLen: U32,
                   outInnerType: var U8, outPlainLen: var U32): bool =
  if outerType != TlsRecordApplicationData:
    return false
  if encryptedLen <= U32(Poly1305TagLen) or encryptedLen > U32(TlsMaxRecord):
    return false

  var nonce: array[12, U8]
  var header: array[5, U8]
  header[0] = TlsRecordApplicationData
  header[1] = 0x03'u8
  header[2] = 0x03'u8
  header[3] = U8((encryptedLen shr 8) and 0xff'u32)
  header[4] = U8(encryptedLen and 0xff'u32)

  let cipherLen = encryptedLen - U32(Poly1305TagLen)
  makeNonce(iv, seq, addr nonce[0])
  if chacha20Poly1305Decrypt(key, addr nonce[0], addr header[0], U32(5),
                             encrypted, cipherLen,
                             cast[pointer](cast[U64](encrypted) + U64(cipherLen)),
                             addr plainBuf[0]) != 0:
    return false

  inc seq
  var endPos = cipherLen
  while endPos > 0 and plainBuf[endPos - 1] == 0:
    dec endPos
  if endPos == 0:
    return false

  outInnerType = plainBuf[endPos - 1]
  outPlainLen = endPos - 1
  true


proc encryptRecord(handle: I32, key, iv: pointer, seq: var U64,
                   innerType: U8, data: pointer, len: U32): I32 =
  if len + 1 + U32(Poly1305TagLen) + 5 > U32(TlsMaxRecord):
    return -1

  copyMem(addr plainBuf[0], data, len)
  plainBuf[len] = innerType
  let plainLen = len + 1
  let encryptedLen = plainLen + U32(Poly1305TagLen)

  var nonce: array[12, U8]
  var header: array[5, U8]
  header[0] = TlsRecordApplicationData
  header[1] = 0x03'u8
  header[2] = 0x03'u8
  header[3] = U8((encryptedLen shr 8) and 0xff'u32)
  header[4] = U8(encryptedLen and 0xff'u32)

  makeNonce(iv, seq, addr nonce[0])
  if chacha20Poly1305Encrypt(key, addr nonce[0], addr header[0], U32(5),
                             addr plainBuf[0], plainLen,
                             addr cipherBuf[0],
                             addr cipherBuf[plainLen]) != 0:
    return -1

  txBuf[0] = header[0]
  txBuf[1] = header[1]
  txBuf[2] = header[2]
  txBuf[3] = header[3]
  txBuf[4] = header[4]
  copyMem(addr txBuf[5], addr cipherBuf[0], encryptedLen)
  let sent = tcpSend(handle, addr txBuf[0], encryptedLen + 5)
  if sent == I32(encryptedLen + 5):
    inc seq
    return I32(len)

  -1


proc verifyFinished(secret: pointer, finishedData: pointer, finishedLen: U32,
                    transcript: var Sha256Ctx): bool =
  if finishedLen != U32(32):
    return false

  var finishedKey: array[32, U8]
  var transcriptHash: array[32, U8]
  var expected: array[32, U8]
  var transcriptCopy = transcript
  sha256Final(transcriptCopy, addr transcriptHash[0])
  discard hkdfExpandLabelSha256(secret, "finished", nil, U32(0), addr finishedKey[0], U32(32))
  hmacSha256(addr finishedKey[0], U32(32), addr transcriptHash[0], U32(32), addr expected[0])
  secureEqual(addr expected[0], finishedData, U32(32))


proc processServerHandshake(client: var TlsClient, data: pointer, len: U32,
                            sawFinished: var bool): bool =
  let input = cast[ptr UncheckedArray[U8]](data)
  var pos = U32(0)
  while pos < len:
    if pos + 4 > len:
      return false

    let msgType = input[pos]
    let msgLen = get24(input, pos + 1)
    if pos + 4 + msgLen > len:
      return false

    let msgPtr = cast[pointer](cast[U64](data) + U64(pos))
    if msgType == TlsHandshakeFinished:
      let verifyPtr = cast[pointer](cast[U64](data) + U64(pos + 4))
      if not verifyFinished(addr client.serverHandshakeSecret[0], verifyPtr, msgLen,
                            client.transcript):
        return false

      sha256Update(client.transcript, msgPtr, msgLen + 4)
      sawFinished = true
      return true

    sha256Update(client.transcript, msgPtr, msgLen + 4)
    pos = pos + 4 + msgLen

  true


proc readServerHandshake(client: var TlsClient): bool =
  var sawFinished = false
  while not sawFinished:
    var contentType = U8(0)
    let recordLen = receiveRecord(client, contentType, addr rxBuf[0], U32(TlsMaxRecord))
    if recordLen <= 0:
      return false

    if contentType == TlsRecordChangeCipherSpec:
      continue
    if contentType != TlsRecordApplicationData:
      return false

    var innerType = U8(0)
    var plainLen = U32(0)
    if not decryptRecord(addr client.serverHandshakeKey[0], addr client.serverHandshakeIv[0],
                         client.serverHandshakeSeq, contentType, addr rxBuf[0],
                         U32(recordLen), innerType, plainLen):
      return false

    if innerType != TlsRecordHandshake:
      return false
    if not processServerHandshake(client, addr plainBuf[0], plainLen, sawFinished):
      return false

  true


proc sendClientFinished(client: var TlsClient): bool =
  var finishedKey: array[32, U8]
  var transcriptHash: array[32, U8]
  var verifyData: array[32, U8]
  var transcriptCopy = client.transcript

  sha256Final(transcriptCopy, addr transcriptHash[0])
  discard hkdfExpandLabelSha256(addr client.clientHandshakeSecret[0], "finished",
                                nil, U32(0), addr finishedKey[0], U32(32))
  hmacSha256(addr finishedKey[0], U32(32), addr transcriptHash[0], U32(32), addr verifyData[0])

  txBuf[0] = TlsHandshakeFinished
  txBuf[1] = 0
  txBuf[2] = 0
  txBuf[3] = 32
  copyMem(addr txBuf[4], addr verifyData[0], U32(32))

  if encryptRecord(client.handle, addr client.clientHandshakeKey[0],
                   addr client.clientHandshakeIv[0], client.clientHandshakeSeq,
                   TlsRecordHandshake, addr txBuf[0], U32(36)) != I32(36):
    return false

  sha256Update(client.transcript, addr txBuf[0], U32(36))
  true


proc deriveApplicationSecrets(client: var TlsClient) =
  var zeros: array[32, U8]
  var emptyHash: array[32, U8]
  var derivedSecret: array[32, U8]
  var masterSecret: array[32, U8]
  var transcriptHash: array[32, U8]
  var emptyCtx = Sha256Ctx()
  var transcriptCopy = client.transcript

  sha256Init(emptyCtx)
  sha256Final(emptyCtx, addr emptyHash[0])
  discard hkdfExpandLabelSha256(addr client.handshakeSecret[0], "derived",
                                addr emptyHash[0], U32(32),
                                addr derivedSecret[0], U32(32))
  hkdfExtractSha256(addr derivedSecret[0], U32(32), addr zeros[0], U32(32),
                    addr masterSecret[0])

  sha256Final(transcriptCopy, addr transcriptHash[0])
  discard hkdfExpandLabelSha256(addr masterSecret[0], "c ap traffic",
                                addr transcriptHash[0], U32(32),
                                addr client.clientAppSecret[0], U32(32))
  discard hkdfExpandLabelSha256(addr masterSecret[0], "s ap traffic",
                                addr transcriptHash[0], U32(32),
                                addr client.serverAppSecret[0], U32(32))
  trafficKey(addr client.clientAppSecret[0], addr client.clientAppKey[0],
             addr client.clientAppIv[0])
  trafficKey(addr client.serverAppSecret[0], addr client.serverAppKey[0],
             addr client.serverAppIv[0])


proc clear*(client: var TlsClient) =
  client.handle = -1
  client.lastError = 0
  client.active = false
  client.clientHandshakeSeq = 0
  client.serverHandshakeSeq = 0
  client.clientAppSeq = 0
  client.serverAppSeq = 0
  client.rawOff = 0
  client.rawLen = 0
  client.appOff = 0
  client.appLen = 0
  zeroMem(addr client.privateKey[0], U32(32))
  zeroMem(addr client.publicKey[0], U32(32))
  zeroMem(addr client.serverPublicKey[0], U32(32))
  zeroMem(addr client.sharedSecret[0], U32(32))
  zeroMem(addr client.handshakeSecret[0], U32(32))
  zeroMem(addr client.clientHandshakeSecret[0], U32(32))
  zeroMem(addr client.serverHandshakeSecret[0], U32(32))
  zeroMem(addr client.clientAppSecret[0], U32(32))
  zeroMem(addr client.serverAppSecret[0], U32(32))
  zeroMem(addr client.clientHandshakeKey[0], U32(32))
  zeroMem(addr client.serverHandshakeKey[0], U32(32))
  zeroMem(addr client.clientAppKey[0], U32(32))
  zeroMem(addr client.serverAppKey[0], U32(32))
  zeroMem(addr client.clientHandshakeIv[0], U32(12))
  zeroMem(addr client.serverHandshakeIv[0], U32(12))
  zeroMem(addr client.clientAppIv[0], U32(12))
  zeroMem(addr client.serverAppIv[0], U32(12))
  sha256Init(client.transcript)


proc tlsClose*(client: var TlsClient): I32


proc tlsConnect*(client: var TlsClient, ip: U32, port: U16, host: cstring): I32 =
  clear(client)
  tlsLastError = 0

  if host == nil or host[0] == '\0':
    client.lastError = -1
    tlsLastError = -1
    return -1

  let handle = tcpConnect(ip, U16(0), port)
  if handle <= 0:
    client.lastError = -1
    tlsLastError = -1
    return -1

  client.handle = handle
  makeKeyPair(client)

  var clientHelloLen = U32(0)
  if not buildClientHello(client, host, clientHelloLen):
    discard tlsClose(client)
    client.lastError = -1
    tlsLastError = -1
    return -1

  sha256Update(client.transcript, addr txBuf[0], clientHelloLen)
  if sendPlainRecord(handle, TlsRecordHandshake, addr txBuf[0], clientHelloLen) != I32(clientHelloLen + 5):
    discard tlsClose(client)
    client.lastError = -1
    tlsLastError = -1
    return -1

  var contentType = U8(0)
  let serverHelloLen = receiveRecord(client, contentType, addr rxBuf[0], U32(TlsMaxRecord))
  if serverHelloLen <= 0 or contentType != TlsRecordHandshake:
    discard tlsClose(client)
    client.lastError = TlsErrBadServerHello
    tlsLastError = TlsErrBadServerHello
    return TlsErrBadServerHello

  if not parseServerHello(client, addr rxBuf[0], U32(serverHelloLen)):
    discard tlsClose(client)
    client.lastError = TlsErrBadServerHello
    tlsLastError = TlsErrBadServerHello
    return TlsErrBadServerHello

  sha256Update(client.transcript, addr rxBuf[0], U32(serverHelloLen))
  if x25519(addr client.sharedSecret[0], addr client.privateKey[0],
            addr client.serverPublicKey[0]) != 0:
    discard tlsClose(client)
    client.lastError = -1
    tlsLastError = -1
    return -1

  deriveHandshakeSecrets(client)
  if not readServerHandshake(client):
    discard tlsClose(client)
    client.lastError = -1
    tlsLastError = -1
    return -1
  deriveApplicationSecrets(client)
  if not sendClientFinished(client):
    discard tlsClose(client)
    client.lastError = -1
    tlsLastError = -1
    return -1

  client.active = true
  client.lastError = 0
  tlsLastError = 0
  client.handle


proc tlsSend*(client: var TlsClient, data: pointer, len: U32): I32 =
  if client.handle <= 0 or data == nil or len == 0:
    return -1

  encryptRecord(client.handle, addr client.clientAppKey[0], addr client.clientAppIv[0],
                client.clientAppSeq, TlsRecordApplicationData, data, len)


proc copyPendingApp(client: var TlsClient, data: pointer, capacity: U32): I32 =
  if client.appLen == 0:
    return 0

  var copyLen = client.appLen
  if copyLen > capacity:
    copyLen = capacity

  copyMem(data, addr appBuf[client.appOff], copyLen)
  client.appOff = client.appOff + copyLen
  client.appLen = client.appLen - copyLen
  if client.appLen == 0:
    client.appOff = 0

  I32(copyLen)


proc tlsReceive*(client: var TlsClient, data: pointer, capacity: U32): I32 =
  if client.handle <= 0 or data == nil or capacity == 0:
    return -1

  let pending = copyPendingApp(client, data, capacity)
  if pending > 0:
    return pending

  while true:
    var contentType = U8(0)
    let recordLen = receiveRecord(client, contentType, addr rxBuf[0], U32(TlsMaxRecord))
    if recordLen < 0:
      return -1
    if recordLen == 0:
      return 0
    if contentType == TlsRecordAlert:
      return 0
    if contentType != TlsRecordApplicationData:
      continue

    var innerType = U8(0)
    var plainLen = U32(0)
    if not decryptRecord(addr client.serverAppKey[0], addr client.serverAppIv[0],
                         client.serverAppSeq, contentType, addr rxBuf[0],
                         U32(recordLen), innerType, plainLen):
      return -1

    if innerType == TlsRecordApplicationData:
      copyMem(addr appBuf[0], addr plainBuf[0], plainLen)
      client.appOff = 0
      client.appLen = plainLen
      return copyPendingApp(client, data, capacity)
    if innerType == TlsRecordAlert:
      return 0
    if innerType == TlsRecordHandshake:
      continue

    return -1


proc tlsClose*(client: var TlsClient): I32 =
  if client.handle > 0:
    let rc = tcpClose(client.handle)
    clear(client)
    return rc

  clear(client)
  0


proc slotIndex(handle: I32): int =
  if handle < TlsHandleBase:
    return -1

  let idx = handle - TlsHandleBase
  if idx < 0 or idx >= TlsSlotCount:
    return -1

  int(idx)


proc tlsOpen*(ip: U32, port: U16, host: cstring): I32 =
  var i = 0
  while i < TlsSlotCount:
    if not tlsSlots[i].active and tlsSlots[i].handle <= 0:
      let rc = tlsConnect(tlsSlots[i], ip, port, host)
      if rc <= 0:
        clear(tlsSlots[i])
        return rc

      tlsSlots[i].active = true
      return TlsHandleBase + I32(i)

    inc i

  -1


proc tlsSendHandle*(handle: I32, data: pointer, len: U32): I32 =
  let idx = slotIndex(handle)
  if idx < 0:
    return -1

  tlsSend(tlsSlots[idx], data, len)


proc tlsReceiveHandle*(handle: I32, data: pointer, capacity: U32): I32 =
  let idx = slotIndex(handle)
  if idx < 0:
    return -1

  tlsReceive(tlsSlots[idx], data, capacity)


proc tlsCloseHandle*(handle: I32): I32 =
  let idx = slotIndex(handle)
  if idx < 0:
    return -1

  tlsClose(tlsSlots[idx])


proc tlsVersionNameHandle*(handle: I32): cstring =
  let idx = slotIndex(handle)
  if idx < 0:
    return cstring("unknown")

  cstring("TLS1.3")


proc tlsCipherNameHandle*(handle: I32): cstring =
  let idx = slotIndex(handle)
  if idx < 0:
    return cstring("unknown")

  cstring("TLS_CHACHA20_POLY1305_SHA256")


proc isTlsHandle*(handle: I32): bool =
  slotIndex(handle) >= 0
