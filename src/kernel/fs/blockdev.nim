## Implements low-level VirtIO block device access.
import ../../arch/riscv64/arch
import ../../lib/types
import ../dev/console
import ../lib/virtio
import volatile

const
  BlockSize* = U64(512)
  BlockCount* = U64(32768)

  VirtioBlkIn = U32(0)
  VirtioBlkOut = U32(1)
  VqNum = U64(8)
  VqBytes = U64(8192)
  VqAlign = U64(4096)
  IoSpinLimit = U64(300000000)
  IoRetryMax = 1

type
  VirtioBlkReqHdr {.packed.} = object
    typ: U32
    reserved: U32
    sector: U64

var
  mmioBase: U64
  capacityBlocks: U64
  vq: VirtQueue
  reqHdr: VirtioBlkReqHdr
  reqStatus: U8
  initialized: bool


## Implements the mmio read kernel helper.
proc mmioRead(off: U64): U32 =
  virtioMmioRead(mmioBase, off)


## Implements the mmio write kernel helper.
proc mmioWrite(off: U64, val: U32) =
  virtioMmioWrite(mmioBase, off, val)


## Finds blk.
proc findBlk(): bool =
  scanVirtioMmio(VirtioDevBlock, mmioBase)


## Sets setup vq layout.
proc setupVqLayout() =
  if not resetVirtQueue(vq, VqNum, VqBytes, VqAlign):
    panic("virtio vq alloc failed")


## Sets setup queue.
proc setupQueue(): bool =
  setupVirtQueue(mmioBase, 0, VqNum, vq)


## Configures device.
proc configureDevice(): bool =
  mmioWrite(RegStatus, 0)
  mmioWrite(RegStatus, StatusAcknowledge)
  mmioWrite(RegStatus, StatusAcknowledge or StatusDriver)

  mmioWrite(RegDeviceFeaturesSel, 0)
  discard mmioRead(RegDeviceFeatures)
  mmioWrite(RegDeviceFeaturesSel, 1)
  let features1 = mmioRead(RegDeviceFeatures)
  if (features1 and (U32(1) shl U32(FeatureVersion1 - 32))) == 0:
    println("[blk] missing VERSION_1")
    return false

  var accept1 = U32(1) shl U32(FeatureVersion1 - 32)
  let ringResetBit = U32(1) shl U32(FeatureRingReset - 32)
  if (features1 and ringResetBit) != 0:
    accept1 = accept1 or ringResetBit

  mmioWrite(RegDriverFeaturesSel, 0)
  mmioWrite(RegDriverFeatures, 0)
  mmioWrite(RegDriverFeaturesSel, 1)
  mmioWrite(RegDriverFeatures, accept1)

  var status = mmioRead(RegStatus) or StatusFeaturesOk
  mmioWrite(RegStatus, status)
  if (mmioRead(RegStatus) and StatusFeaturesOk) == 0:
    println("[blk] FEATURES_OK rejected")
    return false

  if not setupQueue():
    println("[blk] setup queue failed")
    return false

  status = mmioRead(RegStatus) or StatusDriverOk
  mmioWrite(RegStatus, status)
  true


## Reads capacity.
proc readCapacity(): bool =
  let lo = U64(mmioRead(RegConfig + 0))
  let hi = U64(mmioRead(RegConfig + 4))
  capacityBlocks = (hi shl 32) or lo
  capacityBlocks != 0


## Implements the recover device kernel helper.
proc recoverDevice(): bool =
  initialized = false
  setupVqLayout()
  if not configureDevice():
    mmioWrite(RegStatus, StatusFailed)
    return false
  if not readCapacity():
    mmioWrite(RegStatus, StatusFailed)
    return false
  initialized = true
  true


## Implements the do io once kernel helper.
proc doIoOnce(typ: U32, blockIndex: U64, buf: pointer): int =
  reqHdr.typ = typ
  reqHdr.reserved = 0
  reqHdr.sector = blockIndex
  reqStatus = 0xff'u8

  vq.desc[0].paddr = cast[U64](addr reqHdr)
  vq.desc[0].len = U32(sizeof(reqHdr))
  vq.desc[0].flags = DescNext
  vq.desc[0].next = 1

  vq.desc[1].paddr = cast[U64](buf)
  vq.desc[1].len = U32(BlockSize)
  vq.desc[1].flags = DescNext
  if typ == VirtioBlkIn:
    vq.desc[1].flags = vq.desc[1].flags or DescWrite
  vq.desc[1].next = 2

  vq.desc[2].paddr = cast[U64](addr reqStatus)
  vq.desc[2].len = 1
  vq.desc[2].flags = DescWrite
  vq.desc[2].next = 0

  let availIdx = volatileLoad(addr vq.avail.idx)
  volatileStore(addr vq.avail.ring[availIdx mod U16(VqNum)], U16(0))
  arch.fenceRwRw()
  volatileStore(addr vq.avail.idx, availIdx + 1)
  arch.fenceRwRw()
  mmioWrite(RegQueueNotify, 0)

  var spin = U64(0)
  while volatileLoad(addr vq.used.idx) == vq.lastUsedIdx:
    inc spin
    if spin > IoSpinLimit:
      print("[blk] timeout type=")
      printUnsigned(U64(typ))
      print(" block=")
      printUnsigned(blockIndex)
      print(" status=")
      printHex(U64(volatileLoad(addr reqStatus)))
      print(" used=")
      printUnsigned(U64(volatileLoad(addr vq.used.idx)))
      print(" last=")
      printUnsigned(U64(vq.lastUsedIdx))
      putChar('\n')
      return -2

  vq.lastUsedIdx = volatileLoad(addr vq.used.idx)
  arch.fenceRwRw()

  let status = volatileLoad(addr reqStatus)
  if status != 0:
    print("[blk] io error type=")
    printUnsigned(U64(typ))
    print(" block=")
    printUnsigned(blockIndex)
    print(" status=")
    printHex(U64(status))
    putChar('\n')
    return -1
  0


## Implements the do io kernel helper.
proc doIo(typ: U32, blockIndex: U64, buf: pointer): int =
  var attempt = 0
  while attempt <= IoRetryMax:
    let rc = doIoOnce(typ, blockIndex, buf)
    if rc == 0:
      return 0
    if rc != -2:
      return rc

    print("[blk] recovering virtio-blk queue\n")
    if not recoverDevice():
      print("[blk] recover failed\n")
      return -1
    inc attempt

  -1


## Implements the blockdev init kernel helper.
proc blockdevInit*() =
  if not findBlk():
    panic("virtio-blk not found")

  setupVqLayout()
  if not configureDevice():
    mmioWrite(RegStatus, StatusFailed)
    panic("virtio-blk configure failed")
  if not readCapacity():
    mmioWrite(RegStatus, StatusFailed)
    panic("virtio-blk capacity failed")

  initialized = true
  printBootMsg("  virtio-blk OK blocks = ")
  printUnsigned(capacityBlocks)
  putChar('\n')


## Implements the block read kernel helper.
proc blockRead*(blockIndex: U64, outBlock: pointer): int =
  if not initialized or outBlock == nil:
    return -1
  if blockIndex >= BlockCount or blockIndex >= capacityBlocks:
    return -1
  doIo(VirtioBlkIn, blockIndex, outBlock)


## Implements the block write kernel helper.
proc blockWrite*(blockIndex: U64, inBlock: pointer): int =
  if not initialized or inBlock == nil:
    return -1
  if blockIndex >= BlockCount or blockIndex >= capacityBlocks:
    return -1
  doIo(VirtioBlkOut, blockIndex, inBlock)
