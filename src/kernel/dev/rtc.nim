import ../../lib/types
import ../../lib/syscall_types

const
  GoldfishRtcBase = U64(0x101000)
  RtcTimeLow = U32(0x00)
  RtcTimeHigh = U32(0x04)

  NsecPerSec = U64(1_000_000_000)


proc rtcRead32(off: U32): U32 =
  let mmioAddr = GoldfishRtcBase + U64(off)
  var value {.volatile.}: U32 = cast[ptr U32](mmioAddr)[]
  value


proc rtcNowNS(): U64 =
  var
    hi1: U32
    hi2: U32
    lo: U32
  
  while true:
    hi1 = rtcRead32(RtcTimeHigh)
    lo = rtcRead32(RtcTimeLow)
    hi2 = rtcRead32(RtcTimeHigh)

    if hi1 == hi2:
      break

  (U64(hi2) shl 32) or U64(lo)


proc isLeapYear(year: U32): bool =
  (year mod 4 == 0 and year mod 100 != 0) or (year mod 400 == 0)


proc daysInYear(year: U32): U32 =
  if isLeapYear(year):
    366
  else:
    365


proc daysInMonth(year: U32, month: U32): U32 =
  case month
  of 1: 31
  of 2:
    if isLeapYear(year):
      29
    else:
      28
  of 3: 31
  of 4: 30
  of 5: 31
  of 6: 30
  of 7: 31
  of 8: 31
  of 9: 30
  of 10: 31
  of 11: 30
  of 12: 31
  else: 0


proc unixSecondsToDateTime(secInput: U64): SysDateTime =
  var sec = secInput

  result.second = U32(sec mod U64(60))
  sec = sec div U64(60)

  result.minute = U32(sec mod U64(60))
  sec = sec div U64(60)

  result.hour = U32(sec mod U64(24))
  var days = sec div U64(24)

  var year = 1970
  while days >= U64(daysInYear(U32(year))):
    days -= U64(daysInYear(U32(year)))
    inc year
  
  var month = 1
  while days >= U64(daysInMonth(U32(year), U32(month))):
    days -= U64(daysInMonth(U32(year), U32(month)))
    inc month

  result.year = U32(year)
  result.month = U32(month)
  result.day = U32(days) + 1


proc nowDateTime*(): SysDateTime =
  unixSecondsToDateTime(rtcNowNS() div NsecPerSec)


proc put2(buf: var array[32, char], pos: var U32, value: U32) =
  buf[pos] = char(ord('0') + ((value div 10) mod 10))
  inc pos
  buf[pos] = char(ord('0') + (value mod 10))
  inc pos


proc put4(buf: var array[32, char], pos: var U32, value: U32) =
  buf[pos] = char(ord('0') + ((value div 1000) mod 10))
  inc pos
  buf[pos] = char(ord('0') + ((value div 100) mod 10))
  inc pos
  buf[pos] = char(ord('0') + ((value div 10) mod 10))
  inc pos
  buf[pos] = char(ord('0') + (value mod 10))
  inc pos


proc rtcNsToCString*(ns: U64): cstring =
  var buf {.global.}: array[32, char]
  var pos: U32 = 0

  let seconds = ns div NsecPerSec
  let dt = unixSecondsToDateTime(seconds)

  # year
  put4(buf, pos, dt.year)
  buf[pos] = '/'
  inc pos
  # month
  put2(buf, pos, dt.month)
  buf[pos] = '/'
  inc pos
  # day
  put2(buf, pos, dt.day)
  buf[pos] = ' '
  inc pos
  # hour 
  put2(buf, pos, dt.hour)
  buf[pos] = ':'
  inc pos
  # minute
  put2(buf, pos, dt.minute)
  buf[pos] = ':'
  inc pos
  # second
  put2(buf, pos, dt.second)
  
  buf[pos] = '\0'
  cast[cstring](addr buf[0])


proc nowCString*(): cstring =
  let ns = rtcNowNS()
  rtcNsToCString(ns)
