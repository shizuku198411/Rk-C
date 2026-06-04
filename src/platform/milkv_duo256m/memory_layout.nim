## Defines Milk-V Duo 256M physical memory layout constants for bring-up.
import ../../lib/types

const
  MilkvKernelLoadBase* = U64(0x80200000)
  MilkvEarlyManagedStart* = U64(0x80400000)
  MilkvEarlyManagedEnd* = U64(0x84000000)
  MilkvKnownFdtAddr* = U64(0x8a777000)
  MilkvReservedIonStart* = U64(0x8b300000)
  MilkvReservedIonSize* = U64(75 * 1024 * 1024)
  MilkvReservedIonEnd* = MilkvReservedIonStart + MilkvReservedIonSize
  MilkvPinmuxBase* = U64(0x03001000)
  MilkvUart0Base* = U64(0x04140000)
  MilkvSdBase* = U64(0x04310000)
  MilkvGpioEBase* = U64(0x05021000)
  MilkvStatusLedPinmuxOffset* = U64(0x000000ac)
  MilkvStatusLedPin* = U32(2)
  MilkvDeviceMmioSize* = U64(0x00010000)
  MilkvSdBlockSize* = U64(512)
  MilkvAppfsPartitionIndex* = U64(1) # zero-origin, partition 2
  MilkvAppfsLocalStartBlock* = U64(4096)
  MilkvTimerFrequency* = U64(25_000_000)
  MilkvTimerInterruptDelta* = MilkvTimerFrequency div U64(2)
