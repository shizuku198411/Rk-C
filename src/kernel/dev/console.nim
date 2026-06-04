## Implements early, panic, and formatted kernel console I/O.
import ../../arch/riscv64/arch
import ../../lib/types
import ./klog
import ../../platform/console_backend

## Implements the put char kernel helper.
proc putChar*(ch: char) =
  console_backend.putChar(ch)


## Prints char.
proc printChar(ch: char) =
  pushKlogChar(ch)
  putChar(ch)


## Implements the try get char kernel helper.
proc tryGetChar*(): int =
  if (console_backend.inputStatus() and U32(1)) != U32(0):
    return console_backend.readInput()

  console_backend.tryGetFallback()


## Gets char blocking.
proc getCharBlocking*(): char =
  while true:
    let ch = tryGetChar()
    if ch >= 0:
      return char(ch and 0xff)
    arch.wfi()


## Prints print.
proc print*(s: cstring) =
  if s == nil:
    print("(null)")
    return

  var i = 0
  while s[i] != '\0':
    printChar(s[i])
    inc i


## Prints println.
proc println*(s: cstring) =
  print(s)
  printChar('\n')


## Prints console only.
proc printConsoleOnly*(s: cstring) =
  if s == nil:
    printConsoleOnly("(null)")
    return

  var i = 0
  while s[i] != '\0':
    putChar(s[i])
    inc i


## Prints println console only.
proc printlnConsoleOnly*(s: cstring) =
  printConsoleOnly(s)
  putChar('\n')


## Prints boot msg.
proc printBootMsg*(s: cstring) =
  print("[boot] ")
  print(s)


## Prints unsigned.
proc printUnsigned*(value: U64) =
  var digits: array[20, char]
  var i = 0
  var v = value

  if v == 0:
    printChar('0')
    return

  while v > 0:
    digits[i] = char(ord('0') + int(v mod 10))
    inc i
    v = v div 10

  while i > 0:
    dec i
    printChar(digits[i])


## Prints signed.
proc printSigned*(value: int64) =
  if value < 0:
    printChar('-')
    printUnsigned(U64(-value))
  else:
    printUnsigned(U64(value))


## Prints hex.
proc printHex*(value: U64) =
  const table = "0123456789abcdef"
  var digits: array[16, char]
  var i = 0
  var v = value

  if v == 0:
    printChar('0')
    return

  while v > 0:
    digits[i] = table[int(v and 0xf'u64)]
    inc i
    v = v shr 4

  while i > 0:
    dec i
    printChar(digits[i])


## Prints ptr.
proc printPtr*(value: U64) =
  print("0x")
  printHex(value)


## Prints bool.
proc printBool*(value: bool) =
  if value:
    print("true")
  else:
    print("false")


## Reads line.
proc readLine*(buf: ptr UncheckedArray[char], cap: U64): U64 =
  if cap == 0:
    return 0

  var len = U64(0)
  while true:
    let ch = getCharBlocking()

    if ch == '\r' or ch == '\n':
      putChar('\n')
      buf[len] = '\0'
      return len

    if ch == '\b' or ord(ch) == 0x7f:
      if len > 0:
        dec len
        print("\b \b")
      continue

    if ord(ch) < 0x20 or ord(ch) > 0x7e:
      continue

    if len + 1 < cap:
      buf[len] = ch
      inc len
      putChar(ch)


## Implements the panic kernel helper.
proc panic*(msg: cstring) {.noreturn.} =
  print("PANIC: ")
  println(msg)
  while true:
    arch.wfi()
