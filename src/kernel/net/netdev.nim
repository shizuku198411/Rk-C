import ../../arch/riscv64/arch
import ../../lib/mem
import ../../lib/syscall_types
import ../../lib/types
import ../mm/memory
import volatile

const
  VirtioMmioBase = U64(0x10001000)
  VirtioMmioStride = U64(0x1000)
  VirtioMmioMaxDevs = U64(8)

  RegMagic = U64(0x000)
  RegVersion = U64(0x004)
  RegDeviceId = U64(0x008)
  RegVendorId = U64(0x00c)
  RegDeviceFeatures = U64(0x010)
  RegDeviceFeaturesSel = U64(0x014)
  RegDriverFeatures = U64(0x020)
  RegDriverFeaturesSel = U64(0x024)
  RegQueueSel = U64(0x030)
  RegQueueNumMax = U64(0x034)
  RegQueueNum = U64(0x038)
  RegQueueReady = U64(0x044)
  RegQueueNotify = U64(0x050)
  RegStatus = U64(0x070)
  RegQueueDescLow = U64(0x080)
  RegQueueDescHigh = U64(0x084)
  RegQueueAvailLow = U64(0x090)
  RegQueueAvailHigh = U64(0x094)
  RegQueueUsedLow = U64(0x0a0)
  RegQueueUsedHigh = U64(0x0a4)
  RegConfig = U64(0x100)

  VirtioMagic = U32(0x74726976)
  VirtioVendor = U32(0x554d4551)
  VirtioDevNetwork = U32(1)

  StatusAcknowledge = U32(1)
  StatusDriver = U32(2)
  StatusDriverOk = U32(4)
  StatusFeaturesOk = U32(8)
  StatusFailed = U32(128)

  DescWrite = U16(2)
  VqNum = U64(8)
  VqBytes = U64(8192)
  VqAlign = U64(4096)
  NetBufSize = U64(2048)
  NetHdrBaseLen = U64(10)
  NetHdrMrgLen = U64(12)
  TxSpinLimit = U64(30000000)

  FeatureMac = U64(5)
  FeatureMrgRxbuf = U64(15)
  FeatureVersion1 = U64(32)

type
  VirtqDesc {.packed.} = object
    paddr: U64
    len: U32
    flags: U16
    next: U16

  VirtqAvail {.packed.} = object
    flags: U16
    idx: U16
    ring: array[8, U16]
    usedEvent: U16

  VirtqUsedElem {.packed.} = object
    id: U32
    len: U32

  VirtqUsed {.packed.} = object
    flags: U16
    idx: U16
    ring: array[8, VirtqUsedElem]
    availEvent: U16

  VirtQueue = object
    mem: PAddr
    desc: ptr UncheckedArray[VirtqDesc]
    avail: ptr VirtqAvail
    used: ptr VirtqUsed
    lastUsedIdx: U16

var
  mmioBase: U64
  detectedInfo: SysNetDeviceInfo
  rxq: VirtQueue
  txq: VirtQueue
  rxBufMem: PAddr
  txBufMem: PAddr
  txLastUsedIdx: U16
  netHdrLen: U64
  initialized: bool


proc mmioRead(off: U64): U32 =
  volatileLoad(cast[ptr U32](mmioBase + off))


proc mmioWrite(off: U64, val: U32) =
  volatileStore(cast[ptr U32](mmioBase + off), val)


proc readReg(base, off: U64): U32 =
  volatileLoad(cast[ptr U32](base + off))


proc resetQueue(q: var VirtQueue) =
  if q.mem == NilPAddr:
    q.mem = palloc(VqBytes div PageSize)
    if q.mem == NilPAddr:
      return

  zeroMem(cast[pointer](q.mem), VqBytes)
  let descBytes = U64(sizeof(VirtqDesc)) * VqNum
  q.desc = cast[ptr UncheckedArray[VirtqDesc]](q.mem)
  q.avail = cast[ptr VirtqAvail](q.mem + descBytes)
  q.used = cast[ptr VirtqUsed](q.mem + VqAlign)
  q.lastUsedIdx = 0


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


proc featureBit(bit: U64): U32 =
  U32(1) shl U32(bit and 31'u64)


proc readMacConfig() =
  var i = 0
  while i < SysNetMacLen:
    detectedInfo.mac[i] = U8(mmioRead(RegConfig + U64(i)) and 0xff'u32)
    inc i


proc setupQueue(index: U32, q: var VirtQueue): bool =
  resetQueue(q)
  if q.mem == NilPAddr:
    return false

  mmioWrite(RegQueueSel, index)
  let qmax = mmioRead(RegQueueNumMax)
  if qmax == 0 or qmax < U32(VqNum):
    return false

  mmioWrite(RegQueueReady, 0)
  mmioWrite(RegQueueNum, U32(VqNum))
  mmioWrite(RegQueueDescLow, U32(q.mem and 0xffffffff'u64))
  mmioWrite(RegQueueDescHigh, U32(q.mem shr 32))
  mmioWrite(RegQueueAvailLow, U32((cast[U64](q.avail)) and 0xffffffff'u64))
  mmioWrite(RegQueueAvailHigh, U32(cast[U64](q.avail) shr 32))
  mmioWrite(RegQueueUsedLow, U32((cast[U64](q.used)) and 0xffffffff'u64))
  mmioWrite(RegQueueUsedHigh, U32(cast[U64](q.used) shr 32))
  mmioWrite(RegQueueReady, 1)
  true


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


proc setupRxBuffers(): bool =
  if rxBufMem == NilPAddr:
    rxBufMem = palloc(VqNum)
    if rxBufMem == NilPAddr:
      return false

  var i = U64(0)
  while i < VqNum:
    rxq.desc[i].paddr = rxBufMem + i * PageSize
    rxq.desc[i].len = U32(NetBufSize)
    rxq.desc[i].flags = DescWrite
    rxq.desc[i].next = 0
    rxq.avail.ring[i] = U16(i)
    inc i

  arch.fenceRwRw()
  volatileStore(addr rxq.avail.idx, U16(VqNum))
  arch.fenceRwRw()
  mmioWrite(RegQueueNotify, 0)
  true


proc setupTxBuffer(): bool =
  if txBufMem == NilPAddr:
    txBufMem = palloc(1)
    if txBufMem == NilPAddr:
      return false

  txLastUsedIdx = volatileLoad(addr txq.used.idx)
  true


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


proc netdevInfo*(): SysNetDeviceInfo =
  if initialized:
    detectedInfo.initialized = 1
    return detectedInfo

  discard scanVirtioNet()
  detectedInfo


proc netdevMac*(outMac: pointer): int =
  if outMac == nil:
    return -1
  if not initialized and netdevInit() != 0:
    return -1

  discard copyMem(outMac, addr detectedInfo.mac[0], SysNetMacLen)
  0


proc requeueRxDesc(id: U16) =
  let idx = volatileLoad(addr rxq.avail.idx)
  rxq.avail.ring[idx mod U16(VqNum)] = id
  arch.fenceRwRw()
  volatileStore(addr rxq.avail.idx, idx + 1)
  arch.fenceRwRw()
  mmioWrite(RegQueueNotify, 0)


proc netdevRecv*(outBuf: pointer, capacity: U64): int =
  if outBuf == nil or capacity == 0:
    return -1
  if not initialized and netdevInit() != 0:
    return -1

  if volatileLoad(addr rxq.used.idx) == rxq.lastUsedIdx:
    return 0

  let usedElem = rxq.used.ring[rxq.lastUsedIdx mod U16(VqNum)]
  inc rxq.lastUsedIdx
  arch.fenceRwRw()

  let id = U16(usedElem.id)
  if id >= U16(VqNum):
    return -1

  var frameLen = U64(usedElem.len)
  if frameLen <= netHdrLen:
    requeueRxDesc(id)
    return 0

  frameLen -= netHdrLen
  if frameLen > capacity:
    frameLen = capacity
  if frameLen > SysNetPacketMax:
    frameLen = SysNetPacketMax

  discard copyMem(outBuf, cast[pointer](rxBufMem + U64(id) * PageSize + netHdrLen), frameLen)
  requeueRxDesc(id)
  int(frameLen)


proc netdevSend*(inBuf: pointer, size: U64): int =
  if inBuf == nil or size == 0 or size > SysNetPacketMax:
    return -1
  if not initialized and netdevInit() != 0:
    return -1

  zeroMem(cast[pointer](txBufMem), netHdrLen)
  discard copyMem(cast[pointer](txBufMem + netHdrLen), inBuf, size)

  txq.desc[0].paddr = txBufMem
  txq.desc[0].len = U32(netHdrLen + size)
  txq.desc[0].flags = 0
  txq.desc[0].next = 0

  let availIdx = volatileLoad(addr txq.avail.idx)
  txq.avail.ring[availIdx mod U16(VqNum)] = 0
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
