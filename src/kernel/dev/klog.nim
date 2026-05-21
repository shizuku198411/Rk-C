## Maintains the in-kernel circular log buffer.
import ../../lib/types

const
  KernelLogSize* = U64(16384)

var
  logBuf: array[KernelLogSize, char]
  logWritePos: U64
  logUsed: U64
  logDropped*: U64


## Implements the next pos kernel helper.
proc nextPos(pos: U64): U64 =
  (pos + U64(1)) mod KernelLogSize


## Implements the push klog char kernel helper.
proc pushKlogChar*(ch: char) =
  logBuf[logWritePos] = ch
  logWritePos = nextPos(logWritePos)

  if logUsed < KernelLogSize:
    inc logUsed
  else:
    inc logDropped


## Reads klog.
proc readKlog*(dst: ptr UncheckedArray[char], capacity: U64): U64 =
  if dst == nil or capacity == U64(0):
    return U64(0)

  var n = logUsed
  if n > capacity:
    n = capacity

  var start = (logWritePos + KernelLogSize - n) mod KernelLogSize
  var i = U64(0)
  while i < n:
    dst[i] = logBuf[start]
    start = nextPos(start)
    inc i

  n
