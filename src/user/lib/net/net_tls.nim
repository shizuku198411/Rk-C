import ./net_tcp
import ./crypto/aead_chacha20_poly1305
import ./crypto/chacha20
import ./crypto/hkdf
import ./crypto/sha256
import ./crypto/x25519
import ../core/syscall

const
  TlsDefaultPort* = U16(443)
  TlsErrUnsupported* = I32(-2)
  TlsErrBadServerHello* = I32(-3)

  TlsRecordHandshake = U8(22)
  TlsHandshakeClientHello = U8(1)
  TlsHandshakeServerHello = U8(2)
  TlsCipherChacha20Poly1305Sha256 = U16(0x1303)
  TlsGroupX25519 = U16(0x001d)
  TlsVersion13 = U16(0x0304)

  TlsMaxRecord = 2048
  TlsMaxHandshake = 1024

type
  TlsClient* = object
    handle*: I32
    lastError*: I32
    privateKey: array[32, U8]
    publicKey: array[32, U8]
    serverPublicKey: array[32, U8]
    sharedSecret: array[32, U8]
    clientHandshakeSecret: array[32, U8]
    serverHandshakeSecret: array[32, U8]
    transcript: Sha256Ctx

var
  txBuf: array[TlsMaxHandshake, U8]
  rxBuf: array[TlsMaxRecord, U8]


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


proc put8(buf: var array[TlsMaxHandshake, U8], pos: var U32, value: U8): bool =
  if pos >= U32(TlsMaxHandshake):
    return false

  buf[pos] = value
  inc pos
  true


proc put16(buf: var array[TlsMaxHandshake, U8], pos: var U32, value: U16): bool =
  if pos + 2 > U32(TlsMaxHandshake):
    return false

  buf[pos] = U8((value shr 8) and 0xff'u16)
  buf[pos + 1] = U8(value and 0xff'u16)
  pos = pos + 2
  true


proc put24(buf: var array[TlsMaxHandshake, U8], pos: var U32, value: U32): bool =
  if pos + 3 > U32(TlsMaxHandshake):
    return false

  buf[pos] = U8((value shr 16) and 0xff'u32)
  buf[pos + 1] = U8((value shr 8) and 0xff'u32)
  buf[pos + 2] = U8(value and 0xff'u32)
  pos = pos + 3
  true


proc patch16(buf: var array[TlsMaxHandshake, U8], pos: U32, value: U16) =
  buf[pos] = U8((value shr 8) and 0xff'u16)
  buf[pos + 1] = U8(value and 0xff'u16)


proc patch24(buf: var array[TlsMaxHandshake, U8], pos: U32, value: U32) =
  buf[pos] = U8((value shr 16) and 0xff'u32)
  buf[pos + 1] = U8((value shr 8) and 0xff'u32)
  buf[pos + 2] = U8(value and 0xff'u32)


proc copyBytes(buf: var array[TlsMaxHandshake, U8], pos: var U32, data: pointer, len: U32): bool =
  if pos + len > U32(TlsMaxHandshake):
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
  var x = sysTicks() xor (U64(sysGetPid()) shl 32) xor U64(0x9e3779b97f4a7c15'u64)
  var i = U32(0)
  while i < len:
    x = x xor (x shl 13)
    x = x xor (x shr 7)
    x = x xor (x shl 17)
    outBuf[i] = U8((x shr ((i and 7) * 8)) and 0xff'u64)
    inc i


proc makeKeyPair(client: var TlsClient) =
  fillPseudoRandom(addr client.privateKey[0], U32(32))
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
  fillPseudoRandom(addr randomBytes[0], U32(32))
  fillPseudoRandom(addr sessionId[0], U32(32))

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

  if not put16(txBuf, pos, U16(45)):
    return false
  if not put16(txBuf, pos, U16(2)):
    return false
  if not put8(txBuf, pos, U8(1)):
    return false
  if not put8(txBuf, pos, U8(1)):
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


proc sendHandshakeRecord(handle: I32, handshake: pointer, handshakeLen: U32): I32 =
  var record: array[TlsMaxHandshake + 5, U8]
  if handshakeLen + 5 > U32(record.len):
    return -1

  record[0] = TlsRecordHandshake
  record[1] = 0x03'u8
  record[2] = 0x03'u8
  record[3] = U8((handshakeLen shr 8) and 0xff'u32)
  record[4] = U8(handshakeLen and 0xff'u32)
  copyMem(addr record[5], handshake, handshakeLen)

  tcpSend(handle, addr record[0], handshakeLen + 5)


proc receiveRecord(handle: I32, outContentType: var U8, outData: pointer, capacity: U32): I32 =
  var got = U32(0)
  while got < 5:
    let n = tcpReceive(handle, cast[pointer](cast[U64](addr rxBuf[got])), U32(TlsMaxRecord) - got)
    if n <= 0:
      return -1
    got = got + U32(n)

  outContentType = rxBuf[0]
  let recordLen = (U32(rxBuf[3]) shl 8) or U32(rxBuf[4])
  if recordLen > capacity or recordLen > U32(TlsMaxRecord):
    return -1

  while got < recordLen + 5:
    let n = tcpReceive(handle, cast[pointer](cast[U64](addr rxBuf[got])), U32(TlsMaxRecord) - got)
    if n <= 0:
      return -1
    got = got + U32(n)

  copyMem(outData, addr rxBuf[5], recordLen)
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


proc deriveHandshakeSecrets(client: var TlsClient) =
  var zeros: array[32, U8]
  var emptyHash: array[32, U8]
  var earlySecret: array[32, U8]
  var derivedSecret: array[32, U8]
  var handshakeSecret: array[32, U8]
  var transcriptHash: array[32, U8]
  var emptyCtx = Sha256Ctx()

  sha256Init(emptyCtx)
  sha256Final(emptyCtx, addr emptyHash[0])
  hkdfExtractSha256(addr zeros[0], U32(32), addr zeros[0], U32(32), addr earlySecret[0])
  discard hkdfExpandLabelSha256(addr earlySecret[0], "derived", addr emptyHash[0],
                                U32(32), addr derivedSecret[0], U32(32))
  hkdfExtractSha256(addr derivedSecret[0], U32(32), addr client.sharedSecret[0],
                    U32(32), addr handshakeSecret[0])

  var transcriptCopy = client.transcript
  sha256Final(transcriptCopy, addr transcriptHash[0])
  discard hkdfExpandLabelSha256(addr handshakeSecret[0], "c hs traffic",
                                addr transcriptHash[0], U32(32),
                                addr client.clientHandshakeSecret[0], U32(32))
  discard hkdfExpandLabelSha256(addr handshakeSecret[0], "s hs traffic",
                                addr transcriptHash[0], U32(32),
                                addr client.serverHandshakeSecret[0], U32(32))


proc clear*(client: var TlsClient) =
  client.handle = -1
  client.lastError = 0
  zeroMem(addr client.privateKey[0], U32(32))
  zeroMem(addr client.publicKey[0], U32(32))
  zeroMem(addr client.serverPublicKey[0], U32(32))
  zeroMem(addr client.sharedSecret[0], U32(32))
  zeroMem(addr client.clientHandshakeSecret[0], U32(32))
  zeroMem(addr client.serverHandshakeSecret[0], U32(32))
  sha256Init(client.transcript)


proc tlsClose*(client: var TlsClient): I32


proc tlsConnect*(client: var TlsClient, ip: U32, port: U16, host: cstring): I32 =
  clear(client)

  if host == nil or host[0] == '\0':
    client.lastError = -1
    return -1

  let handle = tcpConnect(ip, U16(0), port)
  if handle <= 0:
    client.lastError = -1
    return -1

  client.handle = handle
  makeKeyPair(client)

  var clientHelloLen = U32(0)
  if not buildClientHello(client, host, clientHelloLen):
    discard tlsClose(client)
    client.lastError = -1
    return -1

  sha256Update(client.transcript, addr txBuf[0], clientHelloLen)
  if sendHandshakeRecord(handle, addr txBuf[0], clientHelloLen) != I32(clientHelloLen + 5):
    discard tlsClose(client)
    client.lastError = -1
    return -1

  var contentType = U8(0)
  let serverHelloLen = receiveRecord(handle, contentType, addr rxBuf[0], U32(TlsMaxRecord))
  if serverHelloLen <= 0 or contentType != TlsRecordHandshake:
    discard tlsClose(client)
    client.lastError = TlsErrBadServerHello
    return TlsErrBadServerHello

  if not parseServerHello(client, addr rxBuf[0], U32(serverHelloLen)):
    discard tlsClose(client)
    client.lastError = TlsErrBadServerHello
    return TlsErrBadServerHello

  sha256Update(client.transcript, addr rxBuf[0], U32(serverHelloLen))
  if x25519(addr client.sharedSecret[0], addr client.privateKey[0],
            addr client.serverPublicKey[0]) != 0:
    discard tlsClose(client)
    client.lastError = -1
    return -1

  deriveHandshakeSecrets(client)
  client.lastError = TlsErrUnsupported
  discard tlsClose(client)
  TlsErrUnsupported


proc tlsSend*(client: var TlsClient, data: pointer, len: U32): I32 =
  if client.handle <= 0 or data == nil or len == 0:
    return -1

  TlsErrUnsupported


proc tlsReceive*(client: var TlsClient, data: pointer, capacity: U32): I32 =
  if client.handle <= 0 or data == nil or capacity == 0:
    return -1

  TlsErrUnsupported


proc tlsClose*(client: var TlsClient): I32 =
  if client.handle > 0:
    let rc = tcpClose(client.handle)
    client.handle = -1
    return rc

  0
