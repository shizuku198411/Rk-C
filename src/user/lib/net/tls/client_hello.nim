## Builds TLS ClientHello records, random values, and key shares.

## Writes put8.
proc put8(buf: var array[TlsMaxRecord, U8], pos: var U32, value: U8): bool =
  if pos >= U32(TlsMaxRecord):
    return false

  buf[pos] = value
  inc pos
  true


## Writes put16.
proc put16(buf: var array[TlsMaxRecord, U8], pos: var U32, value: U16): bool =
  if pos + 2 > U32(TlsMaxRecord):
    return false

  buf[pos] = U8((value shr 8) and 0xff'u16)
  buf[pos + 1] = U8(value and 0xff'u16)
  pos = pos + 2
  true


## Writes put24.
proc put24(buf: var array[TlsMaxRecord, U8], pos: var U32, value: U32): bool =
  if pos + 3 > U32(TlsMaxRecord):
    return false

  buf[pos] = U8((value shr 16) and 0xff'u32)
  buf[pos + 1] = U8((value shr 8) and 0xff'u32)
  buf[pos + 2] = U8(value and 0xff'u32)
  pos = pos + 3
  true


## Implements the patch16 helper.
proc patch16(buf: var array[TlsMaxRecord, U8], pos: U32, value: U16) =
  buf[pos] = U8((value shr 8) and 0xff'u16)
  buf[pos + 1] = U8(value and 0xff'u16)


## Implements the patch24 helper.
proc patch24(buf: var array[TlsMaxRecord, U8], pos: U32, value: U32) =
  buf[pos] = U8((value shr 16) and 0xff'u32)
  buf[pos + 1] = U8((value shr 8) and 0xff'u32)
  buf[pos + 2] = U8(value and 0xff'u32)


## Copies bytes.
proc copyBytes(buf: var array[TlsMaxRecord, U8], pos: var U32, data: pointer, len: U32): bool =
  if pos + len > U32(TlsMaxRecord):
    return false

  copyMem(addr buf[pos], data, len)
  pos = pos + len
  true


## Gets get16.
proc get16(data: ptr UncheckedArray[U8], pos: U32): U16 =
  (U16(data[pos]) shl 8) or U16(data[pos + 1])


## Gets get24.
proc get24(data: ptr UncheckedArray[U8], pos: U32): U32 =
  (U32(data[pos]) shl 16) or (U32(data[pos + 1]) shl 8) or U32(data[pos + 2])


## Fills pseudo random.
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


## Fills random.
proc fillRandom(buf: pointer, len: U32) =
  if sysEntropy(buf, U64(len)) == I32(len):
    return

  fillPseudoRandom(buf, len)


## Builds key pair.
proc makeKeyPair(client: var TlsClient) =
  fillRandom(addr client.privateKey[0], U32(32))
  discard x25519Base(addr client.publicKey[0], addr client.privateKey[0])


## Writes server name.
proc writeServerName(host: cstring, pos: var U32): bool =
  let hostLen = U32(cstrlen(host))
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


## Builds client hello.
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


