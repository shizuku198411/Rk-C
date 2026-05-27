## Provides basic stdin/stdout helpers for user programs.
import ./strutils
import ./syscall


## Writes a raw buffer to stdout.
proc writeBuffer*(buf: pointer, len: U64) =
  if buf == nil or len == 0:
    return

  discard sysWriteFd(1, buf, len)


## Writes cstring.
proc write*(s: cstring) =
  if s == nil:
    discard sysWriteFd(1, cast[pointer](cstring"(null)"), cstrlen(cstring"(null)"))
    return

  discard sysWriteFd(1, cast[pointer](s), cstrlen(s))


## Writes char.
##
## This is still useful for interactive input echo, but avoid using it in
## large rendering loops. Prefer writeBuffer/write for bulk output.
proc writeChar*(ch: char) =
  var c = ch
  discard sysWriteFd(1, addr c, 1)


## Reads char.
proc readChar*(): char =
  var c: char
  discard sysReadFd(0, addr c, 1)
  c


## Writes unsigned.
proc writeUnsigned*(value: U64) =
  var buf: array[32, char]
  var n = value
  var pos = 32

  if n == 0:
    buf[31] = '0'
    discard sysWriteFd(1, addr buf[31], 1)
    return

  while n > 0:
    let digit = n mod 10
    dec pos
    buf[pos] = char(ord('0') + int(digit))
    n = n div 10

  discard sysWriteFd(1, addr buf[pos], U64(32 - pos))


## Writes hex value.
proc writeHexValue*(value: U64) =
  var buf: array[18, char]
  var pos = 0

  buf[pos] = '0'
  inc pos
  buf[pos] = 'x'
  inc pos

  if value == U64(0):
    buf[pos] = '0'
    inc pos
    discard sysWriteFd(1, addr buf[0], U64(pos))
    return

  var started = false
  var shift = 60

  while shift >= 0:
    let digit = (value shr U64(shift)) and U64(0xf)

    if digit != U64(0) or started:
      started = true

      if digit < U64(10):
        buf[pos] = char(ord('0') + int(digit))
      else:
        buf[pos] = char(ord('a') + int(digit - U64(10)))

      inc pos

    shift -= 4

  discard sysWriteFd(1, addr buf[0], U64(pos))


## Writes hex32 value.
proc writeHex32Value*(value: U32) =
  writeHexValue(U64(value))