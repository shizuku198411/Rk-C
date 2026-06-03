## Provides a tiny 16550-compatible UART MMIO driver for platform bring-up checks.
import ../../lib/types
import volatile

const
  UartRbr = U64(0)
  UartThr = U64(0)
  UartLsr = U64(5)
  UartLsrDataReady = U32(1 shl 0)
  UartLsrThrEmpty = U32(1 shl 5)
  UartSpinLimit = U64(1_000_000)

type
  Uart16550* = object
    base*: U64
    regShift*: U8
    regWidth*: U8


## Computes the byte offset for a UART register.
proc uartRegOffset(dev: Uart16550, reg: U64): U64 =
  reg shl U64(dev.regShift)


## Reads one UART register using the configured MMIO width.
proc uartRead*(dev: Uart16550, reg: U64): U32 =
  let regAddr = dev.base + uartRegOffset(dev, reg)
  if dev.regWidth == U8(4):
    return volatileLoad(cast[ptr U32](regAddr))

  U32(volatileLoad(cast[ptr U8](regAddr)))


## Writes one UART register using the configured MMIO width.
proc uartWrite*(dev: Uart16550, reg: U64, value: U32) =
  let regAddr = dev.base + uartRegOffset(dev, reg)
  if dev.regWidth == U8(4):
    volatileStore(cast[ptr U32](regAddr), value)
  else:
    volatileStore(cast[ptr U8](regAddr), U8(value and U32(0xff)))


## Returns true when the UART LSR looks usable.
proc uart16550Probe*(dev: Uart16550): bool =
  let lsr = uartRead(dev, UartLsr) and U32(0xff)
  lsr != U32(0xff)


## Writes one byte to a 16550-compatible UART.
proc uart16550PutChar*(dev: Uart16550, ch: char): bool =
  var spin = UartSpinLimit
  while spin > U64(0):
    if (uartRead(dev, UartLsr) and UartLsrThrEmpty) != U32(0):
      uartWrite(dev, UartThr, U32(ord(ch) and 0xff))
      return true
    dec spin

  false


## Reads one byte from a 16550-compatible UART if input is available.
proc uart16550TryGetChar*(dev: Uart16550): int =
  if (uartRead(dev, UartLsr) and UartLsrDataReady) == U32(0):
    return -1

  int(uartRead(dev, UartRbr) and U32(0xff))
