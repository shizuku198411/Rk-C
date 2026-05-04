import ../../../lib/types
import ../../dev/console
import ../../task/process

proc syscallWrite*(buf: U64, len: U64): U64 =
  let p = cast[ptr UncheckedArray[char]](buf)
  var i = U64(0)
  while i < len:
    putChar(p[i])
    inc i
  len

proc syscallRead*(buf: U64, len: U64): U64 =
  if len == 0:
    return 0

  let p = cast[ptr UncheckedArray[char]](buf)
  var i = U64(0)
  while i < len:
    let ch = tryGetChar()
    if ch < 0:
      sleepCurrentForInput()
      continue

    p[i] = char(ch and 0xff)
    inc i
  i
