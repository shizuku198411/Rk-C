## Defines shared VirtIO constants and descriptor structures.
import ../../lib/mem
import ../../lib/types
import ../mm/memory
import volatile


const
  VirtioMmioBase* = U64(0x10001000)
  VirtioMmioStride* = U64(0x1000)
  VirtioMmioMaxDevs* = U64(8)

  RegMagic* = U64(0x000)
  RegVersion* = U64(0x004)
  RegDeviceId* = U64(0x008)
  RegVendorId* = U64(0x00c)
  RegDeviceFeatures* = U64(0x010)
  RegDeviceFeaturesSel* = U64(0x014)
  RegDriverFeatures* = U64(0x020)
  RegDriverFeaturesSel* = U64(0x024)
  RegQueueSel* = U64(0x030)
  RegQueueNumMax* = U64(0x034)
  RegQueueNum* = U64(0x038)
  RegQueueReady* = U64(0x044)
  RegQueueNotify* = U64(0x050)
  RegStatus* = U64(0x070)
  RegQueueDescLow* = U64(0x080)
  RegQueueDescHigh* = U64(0x084)
  RegQueueAvailLow* = U64(0x090)
  RegQueueAvailHigh* = U64(0x094)
  RegQueueUsedLow* = U64(0x0a0)
  RegQueueUsedHigh* = U64(0x0a4)
  RegConfig* = U64(0x100)

  VirtioMagic* = U32(0x74726976)
  VirtioVendor* = U32(0x554d4551)
  VirtioDevNetwork* = U32(1)
  VirtioDevBlock* = U32(2)

  StatusAcknowledge* = U32(1)
  StatusDriver* = U32(2)
  StatusDriverOk* = U32(4)
  StatusFeaturesOk* = U32(8)
  StatusFailed* = U32(128)

  DescNext* = U16(1)
  DescWrite* = U16(2)
  FeatureVersion1* = U64(32)
  FeatureRingReset* = U64(40)
  FeatureMac* = U64(5)
  FeatureMrgRxbuf* = U64(15)
  VirtqRingMax* = 32


type
  VirtqDesc* {.packed.} = object
    paddr*: U64
    len*: U32
    flags*: U16
    next*: U16

  VirtqAvail* {.packed.} = object
    flags*: U16
    idx*: U16
    ring*: array[VirtqRingMax, U16]
    usedEvent*: U16

  VirtqUsedElem* {.packed.} = object
    id*: U32
    len*: U32

  VirtqUsed* {.packed.} = object
    flags*: U16
    idx*: U16
    ring*: array[VirtqRingMax, VirtqUsedElem]
    availEvent*: U16

  VirtQueue* = object
    mem*: PAddr
    desc*: ptr UncheckedArray[VirtqDesc]
    avail*: ptr VirtqAvail
    used*: ptr VirtqUsed
    lastUsedIdx*: U16


## Implements the virtio mmio read kernel helper.
proc virtioMmioRead*(base, off: U64): U32 =
  volatileLoad(cast[ptr U32](base + off))


## Implements the virtio mmio write kernel helper.
proc virtioMmioWrite*(base, off: U64, val: U32) =
  volatileStore(cast[ptr U32](base + off), val)


## Implements the feature bit kernel helper.
proc featureBit*(bit: U64): U32 =
  U32(1) shl U32(bit and 31'u64)


## Scans for virtio mmio.
proc scanVirtioMmio*(deviceId: U32, outBase: var U64): bool =
  var i = U64(0)
  while i < VirtioMmioMaxDevs:
    let base = VirtioMmioBase + i * VirtioMmioStride
    if virtioMmioRead(base, RegMagic) == VirtioMagic and
        virtioMmioRead(base, RegVersion) >= 2 and
        virtioMmioRead(base, RegDeviceId) == deviceId and
        virtioMmioRead(base, RegVendorId) == VirtioVendor:
      outBase = base
      return true
    inc i

  false


## Resets virt queue.
proc resetVirtQueue*(q: var VirtQueue, vqNum, vqBytes, vqAlign: U64): bool =
  if vqNum > U64(VirtqRingMax):
    return false

  if q.mem == NilPAddr:
    #q.mem = palloc(vqBytes div PageSize)
    # The virtqueue memory is expicitly cleared just below.
    # Avoid the extra zero-fill done by palloc().
    q.mem = pallocNoZero(vqBytes div PageSize)
    if q.mem == NilPAddr:
      return false

  zeroMem(cast[pointer](q.mem), vqBytes)
  let descBytes = U64(sizeof(VirtqDesc)) * vqNum
  q.desc = cast[ptr UncheckedArray[VirtqDesc]](q.mem)
  q.avail = cast[ptr VirtqAvail](q.mem + descBytes)
  q.used = cast[ptr VirtqUsed](q.mem + vqAlign)
  q.lastUsedIdx = 0
  true


## Sets setup virt queue.
proc setupVirtQueue*(base: U64, index: U32, vqNum: U64, q: var VirtQueue): bool =
  if q.mem == NilPAddr or q.avail == nil or q.used == nil:
    return false

  virtioMmioWrite(base, RegQueueSel, index)
  let qmax = virtioMmioRead(base, RegQueueNumMax)
  if qmax == 0 or qmax < U32(vqNum):
    return false

  virtioMmioWrite(base, RegQueueReady, 0)
  virtioMmioWrite(base, RegQueueNum, U32(vqNum))
  virtioMmioWrite(base, RegQueueDescLow, U32(q.mem and 0xffffffff'u64))
  virtioMmioWrite(base, RegQueueDescHigh, U32(q.mem shr 32))
  virtioMmioWrite(base, RegQueueAvailLow, U32(cast[U64](q.avail) and 0xffffffff'u64))
  virtioMmioWrite(base, RegQueueAvailHigh, U32(cast[U64](q.avail) shr 32))
  virtioMmioWrite(base, RegQueueUsedLow, U32(cast[U64](q.used) and 0xffffffff'u64))
  virtioMmioWrite(base, RegQueueUsedHigh, U32(cast[U64](q.used) shr 32))
  virtioMmioWrite(base, RegQueueReady, 1)
  true
