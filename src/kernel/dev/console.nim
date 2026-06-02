## Implements SBI console I/O and the kernel input buffer.
import ../../arch/riscv64/arch
import ../../lib/types
import ./klog

const
  InputBufCap = U64(128)


when not defined(platformMilkVDuo256m):
  const
    Uart0Base = U64(0x10000000)
    UartRbr = U64(0)
    UartThr = U64(0)
    UartLsr = U64(5)
    UartLsrDataReady = U8(1 shl 0)
    UartLsrThrEmpty = U8(1 shl 5)


## Imports the SBI getchar routine.
proc sbiGetchar(): clong {.importc: "sbi_getchar", cdecl.}


when defined(platformMilkVDuo256m):
  ## Imports the SBI putchar routine.
  proc sbiPutchar(ch: clong) {.importc: "sbi_putchar", cdecl.}

var
  inputBuf: array[InputBufCap, char]
  inputHead: U64
  inputTail: U64


## Implements the input next kernel helper.
proc inputNext(index: U64): U64 =
  (index + 1'u64) mod InputBufCap


## Implements the input empty kernel helper.
proc inputEmpty*(): bool =
  inputHead == inputTail


## Implements the input full kernel helper.
proc inputFull(): bool =
  inputNext(inputTail) == inputHead


## Implements the push input kernel helper.
proc pushInput(ch: char): bool =
  if inputFull():
    return false

  inputBuf[inputTail] = ch
  inputTail = inputNext(inputTail)
  true


## Implements the pop input kernel helper.
proc popInput*(): int =
  if inputEmpty():
    return -1

  let ch = inputBuf[inputHead]
  inputHead = inputNext(inputHead)
  int(ord(ch))


## Implements the poll input kernel helper.
proc pollInput*(): bool =
  when defined(platformMilkVDuo256m):
    false
  else:
    let uart = cast[ptr UncheckedArray[U8]](Uart0Base)
    var pushed = false

    while (uart[UartLsr] and UartLsrDataReady) != 0:
      if not pushInput(char(uart[UartRbr])):
        discard uart[UartRbr]
        break
      pushed = true

    pushed


when not defined(platformMilkVDuo256m):
  ## Writes one byte directly to the emulated 16550 UART.
  ## On QEMU virt this avoids one SBI ecall per character.
  proc uartPutChar*(ch: char) =
    let uart = cast[ptr UncheckedArray[U8]](Uart0Base)

    while (uart[UartLsr] and UartLsrThrEmpty) == 0:
      discard

    uart[UartThr] = U8(ord(ch) and 0xff)


## Implements the put char kernel helper.
proc putChar*(ch: char) =
  when defined(platformMilkVDuo256m):
    sbiPutchar(clong(ord(ch) and 0xff))
  else:
    uartPutChar(ch)


## Prints char.
proc printChar(ch: char) =
  pushKlogChar(ch)
  putChar(ch)


## Implements the try get char kernel helper.
proc tryGetChar*(): int =
  let buffered = popInput()
  if buffered >= 0:
    return buffered

  discard pollInput()
  let polled = popInput()
  if polled >= 0:
    return polled

  int(sbiGetchar())


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
