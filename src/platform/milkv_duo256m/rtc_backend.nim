## Reads Unix wall-clock time from the Sophgo CV1800 RTC.
import ../../lib/types
import ./memory_layout
import volatile

const
  SecPulseGen = U64(0x1004)
  SecCounterValue = U64(0x1018)
  SelectSecPulse = U32(1'u32 shl 31)
  NanosecondsPerSecond = U64(1_000_000_000)


## Reads one 32-bit CV1800 RTC register.
proc rtcRead32(off: U64): U32 =
  volatileLoad(cast[ptr U32](MilkvRtcBase + off))


## Returns whether the CV1800 internal RTC second pulse is enabled.
proc rtcEnabled(): bool =
  (rtcRead32(SecPulseGen) and SelectSecPulse) == U32(0)


## Returns the CV1800 RTC timestamp as Unix nanoseconds.
proc nowNanoseconds*(): U64 =
  if not rtcEnabled():
    return U64(0)

  U64(rtcRead32(SecCounterValue)) * NanosecondsPerSecond
