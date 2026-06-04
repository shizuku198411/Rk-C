## Implements runtime TTY read and write syscall helpers.
import ../../../lib/calc
import ../../../lib/types
import ../../dev/tty
import ../../mm/usercopy
import ../../task/process


const
  TtyIoChunk = U64(128)


## Returns whether a TTY can be read without blocking.
proc syscallTtyReadReady*(ttyId: I32): bool =
  ttyReadReady(ttyId)


## Writes a user buffer to a TTY.
proc syscallTtyWrite*(ttyId: I32, buf: U64, len: U64): U64 =
  if not ttyValid(ttyId):
    return U64(-1'i64)
  if len == U64(0):
    return U64(0)
  if buf == U64(0):
    return U64(-1'i64)

  var chunk: array[TtyIoChunk, U8]
  var copied = U64(0)
  while copied < len:
    let chunkLen = minU64(TtyIoChunk, len - copied)
    if copyFromUser(addr chunk[0], buf + copied, chunkLen) != 0:
      return U64(-1'i64)

    var i = U64(0)
    while i < chunkLen:
      if not ttyWriteByte(ttyId, chunk[i]):
        return U64(-1'i64)
      inc i

    copied += chunkLen

  len


## Reads currently available TTY bytes after blocking for the first byte.
proc syscallTtyRead*(ttyId: I32, buf: U64, len: U64): U64 =
  if not ttyValid(ttyId):
    return U64(-1'i64)
  if len == U64(0):
    return U64(0)
  if buf == U64(0):
    return U64(-1'i64)

  var chunk: array[TtyIoChunk, U8]
  let chunkLen = minU64(TtyIoChunk, len)
  var copied = U64(0)

  while copied == U64(0):
    let ch = ttyTryReadByte(ttyId)
    if ch < 0:
      sleepCurrentForTtyRead(ttyId)
      continue

    chunk[copied] = U8(ch and 0xff)
    inc copied

  while copied < chunkLen:
    let ch = ttyTryReadByte(ttyId)
    if ch < 0:
      break

    chunk[copied] = U8(ch and 0xff)
    inc copied

  if copyToUser(buf, addr chunk[0], copied) != 0:
    return U64(-1'i64)

  copied
