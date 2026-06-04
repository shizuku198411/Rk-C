## Implements runtime TTY devices backed by the active platform console.
import ../../lib/syscall_types
import ../../lib/types
import ../../platform/console_backend
import ./byte_ring


const
  TtyCount = 1
  TtyRxCapacity = 4096
  InputStatusReady = U32(1 shl 0)
  InputStatusOverrun = U32(1 shl 1)
  InputStatusParity = U32(1 shl 2)
  InputStatusFraming = U32(1 shl 3)
  InputStatusBreak = U32(1 shl 4)

  Tty0Id* = I32(0)


type
  TtyDevice = object
    active: bool
    rawMode: bool
    rx: ByteRing[TtyRxCapacity]
    stats: SysConsoleInfo


var
  ttys: array[TtyCount, TtyDevice]


## Returns whether a TTY identifier names an active device.
proc ttyValid*(ttyId: I32): bool =
  ttyId >= I32(0) and ttyId < I32(TtyCount) and ttys[ttyId].active


## Initializes the runtime TTY device table.
proc ttyInit*() =
  var i = 0
  while i < TtyCount:
    ttys[i] = TtyDevice()
    ttys[i].active = true
    ttys[i].rawMode = true
    inc i


## Records UART line-status errors for a TTY.
proc recordInputErrors(tty: var TtyDevice, status: U32) =
  if (status and InputStatusOverrun) != U32(0):
    inc tty.stats.overrunErrors
    inc tty.stats.dropped
  if (status and (InputStatusParity or InputStatusFraming or InputStatusBreak)) != U32(0):
    inc tty.stats.lineErrors


## Polls platform input into the selected TTY RX queue.
proc ttyPollInput*(ttyId: I32): bool =
  if not ttyValid(ttyId):
    return false

  let tty = addr ttys[ttyId]
  var pushed = false

  while true:
    let status = console_backend.inputStatus()
    recordInputErrors(tty[], status)
    if (status and InputStatusReady) == U32(0):
      break
    if tty.rx.isFull():
      inc tty.stats.fullEvents
      break

    let ch = console_backend.readInput()
    if ch < 0:
      break
    if not tty.rx.push(U8(ch and 0xff)):
      inc tty.stats.fullEvents
      break

    inc tty.stats.received
    pushed = true

  pushed


## Returns whether the selected TTY can be read without blocking.
proc ttyReadReady*(ttyId: I32): bool =
  if not ttyValid(ttyId):
    return false

  if not ttys[ttyId].rx.isEmpty():
    return true

  discard ttyPollInput(ttyId)
  not ttys[ttyId].rx.isEmpty()


## Reads one byte from the selected TTY when available.
proc ttyTryReadByte*(ttyId: I32): int =
  if not ttyValid(ttyId):
    return -1

  var ch = U8(0)
  if ttys[ttyId].rx.pop(ch):
    return int(ch)

  discard ttyPollInput(ttyId)
  if ttys[ttyId].rx.pop(ch):
    return int(ch)

  -1


## Writes one byte to the selected TTY.
proc ttyWriteByte*(ttyId: I32, ch: U8): bool =
  if not ttyValid(ttyId):
    return false

  console_backend.putChar(char(ch))
  true


## Returns a snapshot of the selected TTY input statistics.
proc ttyInfo*(ttyId: I32): SysConsoleInfo =
  if not ttyValid(ttyId):
    return SysConsoleInfo()

  result = ttys[ttyId].stats
  result.capacity = ttys[ttyId].rx.capacity()
  result.buffered = ttys[ttyId].rx.len()
