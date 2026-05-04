import ../arch/riscv64/arch
import ../lib/types

const
  Uart0Base = U64(0x10000000)
  UartRbr = U64(0)
  UartLsr = U64(5)
  UartLsrDataReady = U8(1 shl 0)
  InputBufCap = U64(128)

proc sbiPutchar(ch: char) {.importc: "sbi_putchar", cdecl.}
proc sbiGetchar(): clong {.importc: "sbi_getchar", cdecl.}

var
  inputBuf: array[InputBufCap, char]
  inputHead: U64
  inputTail: U64

proc inputNext(index: U64): U64 =
  (index + 1'u64) mod InputBufCap

proc inputEmpty*(): bool =
  inputHead == inputTail

proc inputFull(): bool =
  inputNext(inputTail) == inputHead

proc pushInput(ch: char): bool =
  if inputFull():
    return false

  inputBuf[inputTail] = ch
  inputTail = inputNext(inputTail)
  true

proc popInput*(): int =
  if inputEmpty():
    return -1

  let ch = inputBuf[inputHead]
  inputHead = inputNext(inputHead)
  int(ord(ch))

proc pollInput*(): bool =
  let uart = cast[ptr UncheckedArray[U8]](Uart0Base)
  var pushed = false

  while (uart[UartLsr] and UartLsrDataReady) != 0:
    if not pushInput(char(uart[UartRbr])):
      discard uart[UartRbr]
      break
    pushed = true

  pushed

proc putChar*(ch: char) =
  sbiPutchar(ch)

proc tryGetChar*(): int =
  let buffered = popInput()
  if buffered >= 0:
    return buffered

  discard pollInput()
  let polled = popInput()
  if polled >= 0:
    return polled

  int(sbiGetchar())

proc getCharBlocking*(): char =
  while true:
    let ch = tryGetChar()
    if ch >= 0:
      return char(ch and 0xff)
    arch.wfi()

proc print*(s: cstring) =
  if s == nil:
    print("(null)")
    return

  var i = 0
  while s[i] != '\0':
    putChar(s[i])
    inc i

proc println*(s: cstring) =
  print(s)
  putChar('\n')

proc printBootMsg*(s: cstring) =
  print("[boot] ")
  print(s)

proc printUnsigned*(value: U64) =
  var digits: array[20, char]
  var i = 0
  var v = value

  if v == 0:
    putChar('0')
    return

  while v > 0:
    digits[i] = char(ord('0') + int(v mod 10))
    inc i
    v = v div 10

  while i > 0:
    dec i
    putChar(digits[i])

proc printSigned*(value: int64) =
  if value < 0:
    putChar('-')
    printUnsigned(U64(-value))
  else:
    printUnsigned(U64(value))

proc printHex*(value: U64) =
  const table = "0123456789abcdef"
  var digits: array[16, char]
  var i = 0
  var v = value

  if v == 0:
    putChar('0')
    return

  while v > 0:
    digits[i] = table[int(v and 0xf'u64)]
    inc i
    v = v shr 4

  while i > 0:
    dec i
    putChar(digits[i])

proc printPtr*(value: U64) =
  print("0x")
  printHex(value)

proc printBool*(value: bool) =
  if value:
    print("true")
  else:
    print("false")

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

proc panic*(msg: cstring) {.noreturn.} =
  print("PANIC: ")
  println(msg)
  while true:
    arch.wfi()
