## Exposes TLS connections and handle-based send and receive operations.

## Clears clear.
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


## Closes a TLS connection and releases its underlying TCP handle.
proc tlsClose*(client: var TlsClient): I32


## Performs TLS connect.
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


## Performs TLS send.
proc tlsSend*(client: var TlsClient, data: pointer, len: U32): I32 =
  if client.handle <= 0 or data == nil or len == 0:
    return -1

  encryptRecord(client.handle, addr client.clientAppKey[0], addr client.clientAppIv[0],
                client.clientAppSeq, TlsRecordApplicationData, data, len)


## Copies pending app.
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


## Performs TLS receive.
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


## Closes a TLS connection and releases its underlying TCP handle.
proc tlsClose*(client: var TlsClient): I32 =
  if client.handle > 0:
    let rc = tcpClose(client.handle)
    clear(client)
    return rc

  clear(client)
  0


## Implements the slot index helper.
proc slotIndex(handle: I32): int =
  if handle < TlsHandleBase:
    return -1

  let idx = handle - TlsHandleBase
  if idx < 0 or idx >= TlsSlotCount:
    return -1

  int(idx)


## Performs TLS open.
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


## Performs TLS send handle.
proc tlsSendHandle*(handle: I32, data: pointer, len: U32): I32 =
  let idx = slotIndex(handle)
  if idx < 0:
    return -1

  tlsSend(tlsSlots[idx], data, len)


## Performs TLS receive handle.
proc tlsReceiveHandle*(handle: I32, data: pointer, capacity: U32): I32 =
  let idx = slotIndex(handle)
  if idx < 0:
    return -1

  tlsReceive(tlsSlots[idx], data, capacity)


## Performs TLS close handle.
proc tlsCloseHandle*(handle: I32): I32 =
  let idx = slotIndex(handle)
  if idx < 0:
    return -1

  tlsClose(tlsSlots[idx])


## Performs TLS version name handle.
proc tlsVersionNameHandle*(handle: I32): cstring =
  let idx = slotIndex(handle)
  if idx < 0:
    return cstring("unknown")

  cstring("TLS1.3")


## Performs TLS cipher name handle.
proc tlsCipherNameHandle*(handle: I32): cstring =
  let idx = slotIndex(handle)
  if idx < 0:
    return cstring("unknown")

  cstring("TLS_CHACHA20_POLY1305_SHA256")


## Returns whether tls handle is true.
proc isTlsHandle*(handle: I32): bool =
  slotIndex(handle) >= 0
