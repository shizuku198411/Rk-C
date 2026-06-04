## Reads Unix wall-clock time from the QEMU Goldfish RTC.
import ../../lib/types
import ./memory_layout
import volatile

const
  RtcTimeLow = U64(0x00)
  RtcTimeHigh = U64(0x04)


## Reads one 32-bit Goldfish RTC register.
proc rtcRead32(off: U64): U32 =
  volatileLoad(cast[ptr U32](QemuRtcBase + off))


## Returns a stable Goldfish RTC timestamp in Unix nanoseconds.
proc nowNanoseconds*(): U64 =
  var
    hiBefore: U32
    hiAfter: U32
    lo: U32

  while true:
    hiBefore = rtcRead32(RtcTimeHigh)
    lo = rtcRead32(RtcTimeLow)
    hiAfter = rtcRead32(RtcTimeHigh)

    if hiBefore == hiAfter:
      return (U64(hiAfter) shl 32) or U64(lo)
