## Implements a minimal TLS client used by HTTPS requests.
import ./net_tcp
import ./crypto/aead_chacha20_poly1305
import ./crypto/chacha20
import ./crypto/crypto_types
import ./crypto/hkdf
import ./crypto/sha256
import ./crypto/x25519
import ../core/strutils
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


## Performs TLS error name.
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


## Performs TLS last error name.
proc tlsLastErrorName*(): cstring =
  tlsErrorName(tlsLastError)


## Performs TLS crypto ready.
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


## Includes builds tls clienthello records, random values, and key shares.
include ./tls/client_hello


## Includes transfers tls records and completes the tls 1.3 handshake.
include ./tls/handshake_records


## Includes exposes tls connections and handle-based send and receive operations.
include ./tls/connection
