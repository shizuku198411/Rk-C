import ./strutils
import ./syscall


proc write*(s: cstring) =
  discard sysWriteFd(1, cast[pointer](s), cstrlen(s))


proc writeChar*(ch: char) =
  var c = ch
  discard sysWriteFd(1, addr c, 1)


proc readChar*(): char =
  var c: char
  discard sysReadFd(0, addr c, 1)
  c


proc writeUnsigned*(value: U64) =
  var buf: array[32, char]
  var n = value
  var pos = 32
  if n == 0:
    writeChar('0')
    return

  while n > 0:
    let digit = n mod 10
    dec pos
    buf[pos] = char(ord('0') + int(digit))
    n = n div 10

  discard sysWriteFd(1, addr buf[pos], U64(32 - pos))


proc writeHexValue*(value: U64) =
  write("0x")

  var started = false
  var shift = 60
  while shift >= 0:
    let digit = (value shr U64(shift)) and U64(0xf)
    if digit != 0 or started or shift == 0:
      started = true
      if digit < U64(10):
        writeChar(char(ord('0') + int(digit)))
      else:
        writeChar(char(ord('a') + int(digit - U64(10))))
    shift -= 4


proc writeHex32Value*(value: U32) =
  writeHexValue(U64(value))
