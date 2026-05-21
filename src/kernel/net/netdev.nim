## Implements low-level VirtIO network device initialization and packet I/O.
import ../../arch/riscv64/arch
import ../../lib/mem
import ../../lib/syscall_types
import ../../lib/types
import ../lib/virtio
import ../mm/memory
import volatile

const
  VqNum = U64(32)
  VqBytes = U64(8192)
  VqAlign = U64(4096)
  NetBufSize = U64(2048)
  NetHdrBaseLen = U64(10)
  NetHdrMrgLen = U64(12)
  TxSpinLimit = U64(30000000)

var
  mmioBase: U64
  detectedInfo: SysNetDeviceInfo
  rxq: VirtQueue
  txq: VirtQueue
  rxBufMem: PAddr
  txBufMem: PAddr
  txLastUsedIdx: U16
  txNextDesc: U16
  rxOrder: array[32, U16]
  rxOrderHead: U16
  rxOrderTail: U16
  netHdrLen: U64
  initialized: bool


## Implements the mmio read kernel helper.
proc mmioRead(off: U64): U32 =
  virtioMmioRead(mmioBase, off)


## Implements the mmio write kernel helper.
proc mmioWrite(off: U64, val: U32) =
  virtioMmioWrite(mmioBase, off, val)


## Reads reg.
proc readReg(base, off: U64): U32 =
  virtioMmioRead(base, off)


## Implements the rx order push kernel helper.
proc rxOrderPush(id: U16) =
  rxOrder[rxOrderTail mod U16(VqNum)] = id
  rxOrderTail = (rxOrderTail + 1) mod U16(VqNum)


## Implements the rx order pop kernel helper.
proc rxOrderPop(): U16 =
  let id = rxOrder[rxOrderHead mod U16(VqNum)]
  rxOrderHead = (rxOrderHead + 1) mod U16(VqNum)
  id


## Resets queue.
proc resetQueue(q: var VirtQueue) =
  discard resetVirtQueue(q, VqNum, VqBytes, VqAlign)


## Scans for virtio net.
proc scanVirtioNet(): bool =
  detectedInfo = SysNetDeviceInfo()

  var i = U64(0)
  while i < VirtioMmioMaxDevs:
    let base = VirtioMmioBase + i * VirtioMmioStride
    let magic = readReg(base, RegMagic)
    let version = readReg(base, RegVersion)
    let deviceId = readReg(base, RegDeviceId)
    let vendorId = readReg(base, RegVendorId)

    if magic == VirtioMagic and version >= 2 and deviceId == VirtioDevNetwork and
        vendorId == VirtioVendor:
      mmioBase = base
      detectedInfo.found = 1
      detectedInfo.mmioBase = base
      detectedInfo.deviceId = deviceId
      detectedInfo.vendorId = vendorId
      return true

    inc i

  false


## Reads mac config.
proc readMacConfig() =
  var i = 0
  while i < SysNetMacLen:
    detectedInfo.mac[i] = U8(mmioRead(RegConfig + U64(i)) and 0xff'u32)
    inc i


## Sets setup queue.
proc setupQueue(index: U32, q: var VirtQueue): bool =
  resetQueue(q)
  if q.mem == NilPAddr:
    return false
  setupVirtQueue(mmioBase, index, VqNum, q)


## Configures device.
proc configureDevice(): bool =
  mmioWrite(RegStatus, 0)
  mmioWrite(RegStatus, StatusAcknowledge)
  mmioWrite(RegStatus, StatusAcknowledge or StatusDriver)

  mmioWrite(RegDeviceFeaturesSel, 0)
  let features0 = mmioRead(RegDeviceFeatures)
  mmioWrite(RegDeviceFeaturesSel, 1)
  let features1 = mmioRead(RegDeviceFeatures)
  if (features1 and featureBit(FeatureVersion1 - 32)) == 0:
    return false

  var accept0 = U32(0)
  if (features0 and featureBit(FeatureMac)) != 0:
    accept0 = accept0 or featureBit(FeatureMac)
  if (features0 and featureBit(FeatureMrgRxbuf)) != 0:
    accept0 = accept0 or featureBit(FeatureMrgRxbuf)
    netHdrLen = NetHdrMrgLen
  else:
    netHdrLen = NetHdrBaseLen

  mmioWrite(RegDriverFeaturesSel, 0)
  mmioWrite(RegDriverFeatures, accept0)
  mmioWrite(RegDriverFeaturesSel, 1)
  mmioWrite(RegDriverFeatures, featureBit(FeatureVersion1 - 32))

  var status = mmioRead(RegStatus) or StatusFeaturesOk
  mmioWrite(RegStatus, status)
  if (mmioRead(RegStatus) and StatusFeaturesOk) == 0:
    return false

  if (accept0 and featureBit(FeatureMac)) != 0:
    readMacConfig()

  if not setupQueue(0, rxq):
    return false
  if not setupQueue(1, txq):
    return false

  status = mmioRead(RegStatus) or StatusDriverOk
  mmioWrite(RegStatus, status)
  true


## Sets setup rx buffers.
proc setupRxBuffers(): bool =
  if rxBufMem == NilPAddr:
    rxBufMem = palloc(VqNum)
    if rxBufMem == NilPAddr:
      return false

  rxOrderHead = 0
  rxOrderTail = 0

  var i = U64(0)
  while i < VqNum:
    rxq.desc[i].paddr = rxBufMem + i * PageSize
    rxq.desc[i].len = U32(NetBufSize)
    rxq.desc[i].flags = DescWrite
    rxq.desc[i].next = 0
    rxq.avail.ring[i] = U16(i)
    rxOrderPush(U16(i))
    inc i

  arch.fenceRwRw()
  volatileStore(addr rxq.avail.idx, U16(VqNum))
  arch.fenceRwRw()
  mmioWrite(RegQueueNotify, 0)
  true


## Sets setup tx buffer.
proc setupTxBuffer(): bool =
  if txBufMem == NilPAddr:
    txBufMem = palloc(VqNum)
    if txBufMem == NilPAddr:
      return false

  txLastUsedIdx = volatileLoad(addr txq.used.idx)
  txNextDesc = 0
  true


## Implements the netdev init kernel helper.
proc netdevInit*(): int =
  if initialized:
    return 0
  if not scanVirtioNet():
    return -1
  if not configureDevice():
    mmioWrite(RegStatus, StatusFailed)
    return -1
  if not setupRxBuffers():
    mmioWrite(RegStatus, StatusFailed)
    return -1
  if not setupTxBuffer():
    mmioWrite(RegStatus, StatusFailed)
    return -1

  initialized = true
  detectedInfo.initialized = 1
  0


## Implements the netdev info kernel helper.
proc netdevInfo*(): SysNetDeviceInfo =
  if initialized:
    detectedInfo.initialized = 1
    return detectedInfo

  discard scanVirtioNet()
  detectedInfo


## Implements the netdev mac kernel helper.
proc netdevMac*(outMac: pointer): int =
  if outMac == nil:
    return -1
  if not initialized and netdevInit() != 0:
    return -1

  discard copyMem(outMac, addr detectedInfo.mac[0], SysNetMacLen)
  0


## Implements the requeue rx desc kernel helper.
proc requeueRxDesc(id: U16) =
  let idx = volatileLoad(addr rxq.avail.idx)
  rxq.avail.ring[idx mod U16(VqNum)] = id
  rxOrderPush(id)
  arch.fenceRwRw()
  volatileStore(addr rxq.avail.idx, idx + 1)
  arch.fenceRwRw()
  mmioWrite(RegQueueNotify, 0)


## Implements the rx num buffers kernel helper.
proc rxNumBuffers(id: U16): U16 =
  if netHdrLen != NetHdrMrgLen:
    return U16(1)

  let base = rxBufMem + U64(id) * PageSize
  let lo = U16(cast[ptr U8](base + 10)[])
  let hi = U16(cast[ptr U8](base + 11)[])
  let n = lo or (hi shl 8)
  if n == 0 or n > U16(VqNum):
    return U16(1)

  n


## Implements the netdev recv kernel helper.
proc netdevRecv*(outBuf: pointer, capacity: U64): int =
  if outBuf == nil or capacity == 0:
    return -1
  if not initialized and netdevInit() != 0:
    return -1

  if volatileLoad(addr rxq.used.idx) == rxq.lastUsedIdx:
    return 0

  arch.fenceRwRw()
  let usedElem = rxq.used.ring[rxq.lastUsedIdx mod U16(VqNum)]
  inc rxq.lastUsedIdx

  let id = U16(usedElem.id)
  if id >= U16(VqNum):
    return -1

  let numBuffers = rxNumBuffers(id)
  var consumed: array[32, U16]
  var i = U16(0)
  while i < numBuffers:
    consumed[i] = rxOrderPop()
    inc i
  var frameLen = U64(usedElem.len)
  if frameLen <= netHdrLen:
    i = 0
    while i < numBuffers:
      requeueRxDesc(consumed[i])
      inc i
    return 0

  frameLen -= netHdrLen
  if frameLen > capacity:
    frameLen = capacity
  if frameLen > SysNetPacketMax:
    frameLen = SysNetPacketMax

  discard copyMem(outBuf, cast[pointer](rxBufMem + U64(id) * PageSize + netHdrLen), frameLen)

  i = 0
  while i < numBuffers:
    requeueRxDesc(consumed[i])
    inc i

  int(frameLen)


## Implements the netdev send kernel helper.
proc netdevSend*(inBuf: pointer, size: U64): int =
  if inBuf == nil or size == 0 or size > SysNetPacketMax:
    return -1
  if not initialized and netdevInit() != 0:
    return -1

  let id = txNextDesc
  txNextDesc = (txNextDesc + 1) mod U16(VqNum)
  let bufAddr = txBufMem + U64(id) * PageSize

  zeroMem(cast[pointer](bufAddr), netHdrLen)
  discard copyMem(cast[pointer](bufAddr + netHdrLen), inBuf, size)

  txq.desc[id].paddr = bufAddr
  txq.desc[id].len = U32(netHdrLen + size)
  txq.desc[id].flags = 0
  txq.desc[id].next = 0

  let availIdx = volatileLoad(addr txq.avail.idx)
  txq.avail.ring[availIdx mod U16(VqNum)] = id
  arch.fenceRwRw()
  volatileStore(addr txq.avail.idx, availIdx + 1)
  arch.fenceRwRw()
  mmioWrite(RegQueueNotify, 1)

  var spin = U64(0)
  while volatileLoad(addr txq.used.idx) == txLastUsedIdx:
    inc spin
    if spin > TxSpinLimit:
      return -1

  txLastUsedIdx = volatileLoad(addr txq.used.idx)
  arch.fenceRwRw()
  int(size)
