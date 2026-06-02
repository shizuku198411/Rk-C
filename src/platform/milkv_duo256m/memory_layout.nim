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
  MilkvUart0Base* = U64(0x04140000)
  MilkvTimerFrequency* = U64(25_000_000)
  MilkvTimerInterruptDelta* = MilkvTimerFrequency div U64(2)
