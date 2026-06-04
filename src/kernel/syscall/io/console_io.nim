## Implements console read/write syscall handlers.
import ../../../lib/types
import ../../../lib/calc
import ../../dev/console
import ../../mm/usercopy
import ../../task/process

const
  ConsoleIoChunk = U64(128)


## Returns whether console input can be read without blocking.
proc syscallConsoleReadReady*(): bool =
  consoleReadReady()


## Handles the console write syscall operation.
proc syscallConsoleWrite*(buf: U64, len: U64): U64 =
  if len == 0:
    return 0
  if buf == 0:
    return U64(-1'i64)

  var chunk: array[ConsoleIoChunk, U8]
  var copied = U64(0)
  while copied < len:
    let chunkLen = minU64(ConsoleIoChunk, len - copied)
    if copyFromUser(addr chunk[0], buf + copied, chunkLen) != 0:
      return U64(-1'i64)

    var i = U64(0)
    while i < chunkLen:
      putChar(char(chunk[i]))
      inc i

    copied += chunkLen

  len


## Handles the console read syscall operation.
proc syscallConsoleRead*(buf: U64, len: U64): U64 =
  if len == 0:
    return 0
  if buf == 0:
    return U64(-1'i64)

  var chunk: array[ConsoleIoChunk, U8]
  let chunkLen = minU64(ConsoleIoChunk, len)
  var copied = U64(0)

  while copied == U64(0):
    let ch = tryGetChar()
    if ch < 0:
      sleepCurrentForInput()
      continue

    chunk[copied] = U8(ch and 0xff)
    inc copied

  while copied < chunkLen:
    let ch = tryGetChar()
    if ch < 0:
      break

    chunk[copied] = U8(ch and 0xff)
    inc copied

  if copyToUser(buf, addr chunk[0], copied) != 0:
    return U64(-1'i64)

  copied
