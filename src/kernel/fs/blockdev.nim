## Implements low-level block device access for the active platform.
import ../../lib/types
import ../dev/console

when defined(platformMilkVDuo256m):
  import ../dev/sd/sdhci
  import ../../platform/milkv_duo256m/memory_layout
else:
  import ../../arch/riscv64/arch
  import ../lib/virtio
  import volatile

const
  BlockSize* = U64(512)

when defined(platformMilkVDuo256m):
  const
    BlockCount* = U64(67_108_864)
else:
  const
    BlockCount* = U64(32768)

when not defined(platformMilkVDuo256m):
  const
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
  capacityBlocks: U64
  blockBaseOffset: U64
  initialized: bool

when not defined(platformMilkVDuo256m):
  var
    mmioBase: U64
    vq: VirtQueue
    reqHdr: VirtioBlkReqHdr
    reqStatus: U8


## Implements the mmio read kernel helper.
when not defined(platformMilkVDuo256m):
  proc mmioRead(off: U64): U32 =
    virtioMmioRead(mmioBase, off)


## Implements the mmio write kernel helper.
when not defined(platformMilkVDuo256m):
  proc mmioWrite(off: U64, val: U32) =
    virtioMmioWrite(mmioBase, off, val)


## Finds blk.
when not defined(platformMilkVDuo256m):
  proc findBlk(): bool =
    scanVirtioMmio(VirtioDevBlock, mmioBase)


## Sets setup vq layout.
when not defined(platformMilkVDuo256m):
  proc setupVqLayout() =
    if not resetVirtQueue(vq, VqNum, VqBytes, VqAlign):
      panic("virtio vq alloc failed")


## Sets setup queue.
when not defined(platformMilkVDuo256m):
  proc setupQueue(): bool =
    setupVirtQueue(mmioBase, 0, VqNum, vq)


## Configures device.
when not defined(platformMilkVDuo256m):
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
when not defined(platformMilkVDuo256m):
  proc readCapacity(): bool =
    let lo = U64(mmioRead(RegConfig + 0))
    let hi = U64(mmioRead(RegConfig + 4))
    capacityBlocks = (hi shl 32) or lo
    capacityBlocks != 0


## Implements the recover device kernel helper.
when not defined(platformMilkVDuo256m):
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
when not defined(platformMilkVDuo256m):
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
when not defined(platformMilkVDuo256m):
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


## Translates a logical block index into the active device LBA.
proc physicalBlockIndex(blockIndex: U64, outPhysical: var U64): bool =
  if blockIndex >= capacityBlocks:
    return false
  if blockBaseOffset + blockIndex < blockBaseOffset:
    return false

  let physical = blockBaseOffset + blockIndex
  if physical >= BlockCount:
    return false

  outPhysical = physical
  true


## Implements the blockdev init kernel helper.
proc blockdevInit*() =
  when defined(platformMilkVDuo256m):
    capacityBlocks = BlockCount
    blockBaseOffset = U64(0)
    initialized = true
    printBootMsg("  milkv sd OK blocks = ")
    printUnsigned(capacityBlocks)
    putChar('\n')
  else:
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


## Restricts logical block operations to a partition or reserved range.
proc blockdevSetLogicalRange*(baseOffset, blockCount: U64): bool =
  if not initialized:
    return false
  if blockCount == U64(0):
    return false
  if baseOffset + blockCount < baseOffset:
    return false
  if baseOffset + blockCount > BlockCount:
    return false

  blockBaseOffset = baseOffset
  capacityBlocks = blockCount
  true


## Returns the current logical block base offset on the underlying device.
proc blockdevBaseOffset*(): U64 =
  blockBaseOffset


## Returns the current logical block capacity.
proc blockdevCapacityBlocks*(): U64 =
  capacityBlocks


## Implements the block read kernel helper.
proc blockRead*(blockIndex: U64, outBlock: pointer): int =
  if not initialized or outBlock == nil:
    return -1

  var physical = U64(0)
  if not physicalBlockIndex(blockIndex, physical):
    return -1

  when defined(platformMilkVDuo256m):
    let read = readBlock(MilkvSdBase, physical, outBlock)
    if read.ok:
      return 0
    printBootMsg("  milkv sd read failed block = ")
    printUnsigned(blockIndex)
    print(" physical = ")
    printUnsigned(physical)
    print(" stage = ")
    printUnsigned(U64(ord(read.stage)))
    print(" int = ")
    printHex(U64(read.intStatus))
    print(" state = ")
    printHex(U64(read.presentState))
    putChar('\n')
    return -1
  else:
    doIo(VirtioBlkIn, physical, outBlock)


## Implements the block write kernel helper.
proc blockWrite*(blockIndex: U64, inBlock: pointer): int =
  if not initialized or inBlock == nil:
    return -1

  var physical = U64(0)
  if not physicalBlockIndex(blockIndex, physical):
    return -1

  when defined(platformMilkVDuo256m):
    let write = writeBlock(MilkvSdBase, physical, inBlock)
    if write.ok:
      return 0
    printBootMsg("  milkv sd write failed block = ")
    printUnsigned(blockIndex)
    print(" physical = ")
    printUnsigned(physical)
    print(" stage = ")
    printUnsigned(U64(ord(write.stage)))
    print(" int = ")
    printHex(U64(write.intStatus))
    print(" state = ")
    printHex(U64(write.presentState))
    putChar('\n')
    return -1
  else:
    doIo(VirtioBlkOut, physical, inBlock)
