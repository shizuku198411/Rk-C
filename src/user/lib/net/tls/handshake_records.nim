## Transfers TLS records and completes the TLS 1.3 handshake.

## Sends plain record.
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


## Implements the compact raw helper.
proc compactRaw(client: var TlsClient) =
  if client.rawOff == 0:
    return

  var i = U32(0)
  while i < client.rawLen:
    rawBuf[i] = rawBuf[client.rawOff + i]
    inc i

  client.rawOff = 0


## Fills raw.
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


## Reads raw.
proc readRaw(client: var TlsClient, outData: pointer, len: U32): bool =
  if not fillRaw(client, len):
    return false

  copyMem(outData, addr rawBuf[client.rawOff], len)
  client.rawOff = client.rawOff + len
  client.rawLen = client.rawLen - len
  if client.rawLen == 0:
    client.rawOff = 0

  true


## Receives record.
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


## Parses server hello.
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


## Implements the traffic key helper.
proc trafficKey(secret, outKey, outIv: pointer) =
  discard hkdfExpandLabelSha256(secret, "key", nil, U32(0), outKey, U32(32))
  discard hkdfExpandLabelSha256(secret, "iv", nil, U32(0), outIv, U32(12))


## Derives handshake secrets.
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


## Builds nonce.
proc makeNonce(iv: pointer, seq: U64, outNonce: pointer) =
  copyMem(outNonce, iv, U32(12))
  let nonce = cast[ptr UncheckedArray[U8]](outNonce)
  var i = 0
  while i < 8:
    nonce[4 + i] = nonce[4 + i] xor U8((seq shr U64((7 - i) * 8)) and 0xff'u64)
    inc i


## Decrypts record.
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


## Encrypts record.
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


## Verifies finished.
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


## Implements the process server handshake helper.
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


## Reads server handshake.
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


## Sends client finished.
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


## Derives application secrets.
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


