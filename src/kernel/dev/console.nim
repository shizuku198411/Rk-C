## Implements SBI console I/O and the kernel input buffer.
import ../../arch/riscv64/arch
import ../../lib/types
import ../../lib/syscall_types
import ./byte_ring
import ./klog
import ../../platform/console_backend

const
  InputBufCap = 4096
  InputStatusReady = U32(1 shl 0)
  InputStatusOverrun = U32(1 shl 1)
  InputStatusParity = U32(1 shl 2)
  InputStatusFraming = U32(1 shl 3)
  InputStatusBreak = U32(1 shl 4)


var
  inputRing: ByteRing[InputBufCap]
  inputStats: SysConsoleInfo


## Implements the input empty kernel helper.
proc inputEmpty*(): bool =
  inputRing.isEmpty()


## Implements the input full kernel helper.
proc inputFull(): bool =
  inputRing.isFull()


## Implements the push input kernel helper.
proc pushInput(ch: U8): bool =
  inputRing.push(ch)


## Implements the pop input kernel helper.
proc popInput*(): int =
  var ch = U8(0)
  if not inputRing.pop(ch):
    return -1

  int(ch)


## Records UART line-status errors observed while polling input.
proc recordInputErrors(status: U32) =
  if (status and InputStatusOverrun) != U32(0):
    inc inputStats.overrunErrors
    inc inputStats.dropped
  if (status and (InputStatusParity or InputStatusFraming or InputStatusBreak)) != U32(0):
    inc inputStats.lineErrors


## Implements the poll input kernel helper.
proc pollInput*(): bool =
  var pushed = false

  while true:
    let status = console_backend.inputStatus()
    recordInputErrors(status)
    if (status and InputStatusReady) == U32(0):
      break
    if inputFull():
      inc inputStats.fullEvents
      break

    let ch = console_backend.readInput()
    if ch < 0:
      break
    if not pushInput(U8(ch and 0xff)):
      inc inputStats.fullEvents
      break

    inc inputStats.received
    pushed = true

  pushed


## Returns a snapshot of console input statistics.
proc consoleInfo*(): SysConsoleInfo =
  result = inputStats
  result.capacity = inputRing.capacity()
  result.buffered = inputRing.len()


## Returns whether console input is currently readable.
proc consoleReadReady*(): bool =
  if not inputEmpty():
    return true

  discard pollInput()
  not inputEmpty()


## Implements the put char kernel helper.
proc putChar*(ch: char) =
  console_backend.putChar(ch)


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

  let fallback = console_backend.tryGetFallback()
  if fallback >= 0:
    inc inputStats.received
  fallback


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
