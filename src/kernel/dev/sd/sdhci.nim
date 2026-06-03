## Provides a minimal SDHCI-style SD card probe and single-block PIO read/write path.
import ../../../arch/riscv64/arch
import ../../../lib/types
import volatile

const
  SdhciBlockSize = U64(512)
  RegBlockSize = U64(0x04)
  RegBlockCount = U64(0x06)
  RegArgument = U64(0x08)
  RegTransferMode = U64(0x0c)
  RegCommand = U64(0x0e)
  RegBufferData = U64(0x20)
  RegPresentState = U64(0x24)
  RegPowerControl = U64(0x29)
  RegClockControl = U64(0x2c)
  RegSoftwareReset = U64(0x2f)
  RegIntStatus = U64(0x30)
  RegIntEnable = U64(0x34)
  RegSignalEnable = U64(0x38)
  RegCapabilities = U64(0x40)
  RegHostVersion = U64(0xfe)

  PresentCmdInhibit = U32(1 shl 0)
  PresentDatInhibit = U32(1 shl 1)
  IntCommandComplete = U32(1 shl 0)
  IntTransferComplete = U32(1 shl 1)
  IntBufferWriteReady = U32(1 shl 4)
  IntBufferReadReady = U32(1 shl 5)
  IntErrorMask = U32(0xffff0000)
  ResetAll = U8(1 shl 0)
  Cmd17ReadSingleBlock = U16((17 shl 8) or 0x3a)
  Cmd24WriteSingleBlock = U16((24 shl 8) or 0x3a)
  TransferBlockCountEnable = U16(1 shl 1)
  TransferWrite = TransferBlockCountEnable
  TransferRead = TransferBlockCountEnable or U16(1 shl 4)
  SpinLimit = U64(4_000_000)

type
  SdhciProbeResult* = object
    hostVersion*: U16
    presentState*: U32
    capabilities*: U64
    clockControl*: U16
    powerControl*: U8

  SdhciReadStage* = enum
    sdhciReadNotStarted,
    sdhciReadWaitReady,
    sdhciReadWaitCommand,
    sdhciReadWaitBuffer,
    sdhciReadData,
    sdhciReadWaitTransfer,
    sdhciReadDone,
    sdhciReadError

  SdhciReadResult* = object
    ok*: bool
    stage*: SdhciReadStage
    intStatus*: U32
    presentState*: U32
    wordsRead*: U64

  SdhciWriteStage* = enum
    sdhciWriteNotStarted,
    sdhciWriteWaitReady,
    sdhciWriteWaitCommand,
    sdhciWriteWaitBuffer,
    sdhciWriteData,
    sdhciWriteWaitTransfer,
    sdhciWriteDone,
    sdhciWriteError

  SdhciWriteResult* = object
    ok*: bool
    stage*: SdhciWriteStage
    intStatus*: U32
    presentState*: U32
    wordsWritten*: U64


## Returns the aligned 32-bit register address for a byte/halfword register.
proc aligned32Offset(off: U64): U64 =
  off and not U64(3)


## Returns the bit shift of a byte/halfword register inside an aligned 32-bit word.
proc aligned32Shift(off: U64): U32 =
  U32((off and U64(3)) * U64(8))


## Reads an aligned 32-bit SDHCI register.
proc read32Aligned(base, off: U64): U32 =
  volatileLoad(cast[ptr U32](base + aligned32Offset(off)))


## Writes an aligned 32-bit SDHCI register.
proc write32Aligned(base, off: U64, value: U32) =
  volatileStore(cast[ptr U32](base + aligned32Offset(off)), value)


## Reads an 8-bit SDHCI register through an aligned 32-bit access.
proc read8(base, off: U64): U8 =
  let shift = aligned32Shift(off)
  U8((read32Aligned(base, off) shr shift) and U32(0xff))


## Reads a 16-bit SDHCI register through an aligned 32-bit access.
proc read16(base, off: U64): U16 =
  let shift = aligned32Shift(off)
  U16((read32Aligned(base, off) shr shift) and U32(0xffff))


## Reads a 32-bit SDHCI register.
proc read32(base, off: U64): U32 =
  volatileLoad(cast[ptr U32](base + off))


## Writes an 8-bit SDHCI register through an aligned 32-bit read/modify/write.
proc write8(base, off: U64, value: U8) =
  let shift = aligned32Shift(off)
  let mask = U32(0xff) shl shift
  let oldValue = read32Aligned(base, off)
  let newValue = (oldValue and not mask) or (U32(value) shl shift)
  write32Aligned(base, off, newValue)


## Writes a 16-bit SDHCI register.
##
## Command/transfer registers are write-sensitive on this controller, so writes
## use native halfword stores while reads remain aligned for sparse high offsets.
proc write16(base, off: U64, value: U16) =
  volatileStore(cast[ptr U16](base + off), value)


## Writes a 32-bit SDHCI register.
proc write32(base, off: U64, value: U32) =
  volatileStore(cast[ptr U32](base + off), value)


## Reads the SDHCI capability and state registers without changing device state.
proc probeSdhci*(base: U64): SdhciProbeResult =
  result.hostVersion = read16(base, RegHostVersion)
  result.presentState = read32(base, RegPresentState)
  let capLo = U64(read32(base, RegCapabilities))
  let capHi = U64(read32(base, RegCapabilities + U64(4)))
  result.capabilities = capLo or (capHi shl 32)
  result.clockControl = read16(base, RegClockControl)
  result.powerControl = read8(base, RegPowerControl)


## Waits until the selected interrupt status bits are set or an error appears.
proc waitInterrupt(base: U64, bits: U32, stage: SdhciReadStage, res: var SdhciReadResult): bool =
  var spin = SpinLimit
  while spin > U64(0):
    let status = read32(base, RegIntStatus)
    if (status and IntErrorMask) != U32(0):
      res.stage = stage
      res.intStatus = status
      res.presentState = read32(base, RegPresentState)
      return false

    if (status and bits) == bits:
      res.intStatus = status
      return true

    dec spin

  res.stage = stage
  res.intStatus = read32(base, RegIntStatus)
  res.presentState = read32(base, RegPresentState)
  false


## Waits until the selected interrupt status bits are set or an error appears for writes.
proc waitWriteInterrupt(base: U64, bits: U32, stage: SdhciWriteStage, res: var SdhciWriteResult): bool =
  var spin = SpinLimit
  while spin > U64(0):
    let status = read32(base, RegIntStatus)
    if (status and IntErrorMask) != U32(0):
      res.stage = stage
      res.intStatus = status
      res.presentState = read32(base, RegPresentState)
      return false

    if (status and bits) == bits:
      res.intStatus = status
      return true

    dec spin

  res.stage = stage
  res.intStatus = read32(base, RegIntStatus)
  res.presentState = read32(base, RegPresentState)
  false


## Waits until command/data inhibit bits are clear.
proc waitReady(base: U64, res: var SdhciReadResult): bool =
  res.stage = sdhciReadWaitReady
  var spin = SpinLimit
  while spin > U64(0):
    let state = read32(base, RegPresentState)
    if (state and (PresentCmdInhibit or PresentDatInhibit)) == U32(0):
      res.presentState = state
      return true
    dec spin

  res.presentState = read32(base, RegPresentState)
  res.intStatus = read32(base, RegIntStatus)
  false


## Waits until command/data inhibit bits are clear for writes.
proc waitWriteReady(base: U64, res: var SdhciWriteResult): bool =
  res.stage = sdhciWriteWaitReady
  var spin = SpinLimit
  while spin > U64(0):
    let state = read32(base, RegPresentState)
    if (state and (PresentCmdInhibit or PresentDatInhibit)) == U32(0):
      res.presentState = state
      return true
    dec spin

  res.presentState = read32(base, RegPresentState)
  res.intStatus = read32(base, RegIntStatus)
  false


## Performs a conservative SDHCI setup while preserving the bootloader-provided card state.
proc prepareSdhci(base: U64) =
  write32(base, RegIntStatus, U32(0xffffffff))
  write32(base, RegIntEnable, U32(0xffffffff))
  write32(base, RegSignalEnable, U32(0))
  if read8(base, RegPowerControl) == U8(0):
    write8(base, RegPowerControl, U8(0x0f))
  if read16(base, RegClockControl) == U16(0):
    write16(base, RegClockControl, U16(0x0005))
  arch.fenceRwRw()


## Resets the SDHCI host controller and waits for reset completion.
proc resetSdhci*(base: U64): bool =
  write8(base, RegSoftwareReset, ResetAll)
  var spin = SpinLimit
  while spin > U64(0):
    if (read8(base, RegSoftwareReset) and ResetAll) == U8(0):
      return true
    dec spin

  false


## Reads one 512-byte sector through SDHCI PIO into the supplied buffer.
proc readBlock*(base, blockIndex: U64, buf: pointer): SdhciReadResult =
  result.stage = sdhciReadNotStarted
  if buf == nil:
    result.stage = sdhciReadError
    return

  prepareSdhci(base)
  if not waitReady(base, result):
    result.stage = sdhciReadWaitReady
    return

  write32(base, RegIntStatus, U32(0xffffffff))
  write16(base, RegBlockSize, U16(SdhciBlockSize))
  write16(base, RegBlockCount, U16(1))
  write32(base, RegArgument, U32(blockIndex))
  write16(base, RegTransferMode, TransferRead)
  arch.fenceRwRw()
  write16(base, RegCommand, Cmd17ReadSingleBlock)

  result.stage = sdhciReadWaitCommand
  if not waitInterrupt(base, IntCommandComplete, sdhciReadWaitCommand, result):
    return
  write32(base, RegIntStatus, IntCommandComplete)

  result.stage = sdhciReadWaitBuffer
  if not waitInterrupt(base, IntBufferReadReady, sdhciReadWaitBuffer, result):
    return

  result.stage = sdhciReadData
  let dst = cast[ptr UncheckedArray[U32]](buf)
  var i = U64(0)
  while i < SdhciBlockSize div U64(4):
    dst[i] = read32(base, RegBufferData)
    inc i
  result.wordsRead = i
  write32(base, RegIntStatus, IntBufferReadReady)

  result.stage = sdhciReadWaitTransfer
  if not waitInterrupt(base, IntTransferComplete, sdhciReadWaitTransfer, result):
    return
  write32(base, RegIntStatus, IntTransferComplete)

  result.stage = sdhciReadDone
  result.ok = true


## Reads LBA 0 through SDHCI PIO into the supplied buffer.
proc readLba0*(base: U64, buf: pointer): SdhciReadResult =
  readBlock(base, U64(0), buf)


## Writes one 512-byte sector through SDHCI PIO from the supplied buffer.
proc writeBlock*(base, blockIndex: U64, buf: pointer): SdhciWriteResult =
  result.stage = sdhciWriteNotStarted
  if buf == nil:
    result.stage = sdhciWriteError
    return

  prepareSdhci(base)
  if not waitWriteReady(base, result):
    result.stage = sdhciWriteWaitReady
    return

  write32(base, RegIntStatus, U32(0xffffffff))
  write16(base, RegBlockSize, U16(SdhciBlockSize))
  write16(base, RegBlockCount, U16(1))
  write32(base, RegArgument, U32(blockIndex))
  write16(base, RegTransferMode, TransferWrite)
  arch.fenceRwRw()
  write16(base, RegCommand, Cmd24WriteSingleBlock)

  result.stage = sdhciWriteWaitCommand
  if not waitWriteInterrupt(base, IntCommandComplete, sdhciWriteWaitCommand, result):
    return
  write32(base, RegIntStatus, IntCommandComplete)

  result.stage = sdhciWriteWaitBuffer
  if not waitWriteInterrupt(base, IntBufferWriteReady, sdhciWriteWaitBuffer, result):
    return

  result.stage = sdhciWriteData
  let src = cast[ptr UncheckedArray[U32]](buf)
  var i = U64(0)
  while i < SdhciBlockSize div U64(4):
    write32(base, RegBufferData, src[i])
    inc i
  result.wordsWritten = i
  write32(base, RegIntStatus, IntBufferWriteReady)
  arch.fenceRwRw()

  result.stage = sdhciWriteWaitTransfer
  if not waitWriteInterrupt(base, IntTransferComplete, sdhciWriteWaitTransfer, result):
    return
  write32(base, RegIntStatus, IntTransferComplete)

  result.stage = sdhciWriteDone
  result.ok = true
