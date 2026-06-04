## Provides QEMU virt console I/O backend routines.
import ../../lib/types
import ./memory_layout

const
  UartRbr = U64(0)
  UartThr = U64(0)
  UartLsr = U64(5)
  UartLsrDataReady = U32(1 shl 0)
  UartLsrOverrunError = U32(1 shl 1)
  UartLsrParityError = U32(1 shl 2)
  UartLsrFramingError = U32(1 shl 3)
  UartLsrBreakInterrupt = U32(1 shl 4)
  UartLsrThrEmpty = U8(1 shl 5)


## Imports the SBI getchar routine used as a fallback.
proc sbiGetchar(): clong {.importc: "sbi_getchar", cdecl.}


## Reads the normalized QEMU UART input status.
proc inputStatus*(): U32 =
  let uart = cast[ptr UncheckedArray[U8]](QemuUart0Base)
  U32(uart[UartLsr]) and (
    UartLsrDataReady or UartLsrOverrunError or UartLsrParityError or
    UartLsrFramingError or UartLsrBreakInterrupt
  )


## Reads one byte from the QEMU UART receive register.
proc readInput*(): int =
  let uart = cast[ptr UncheckedArray[U8]](QemuUart0Base)
  int(uart[UartRbr])


## Writes one byte directly to the QEMU emulated 16550 UART.
proc putChar*(ch: char) =
  let uart = cast[ptr UncheckedArray[U8]](QemuUart0Base)

  while (uart[UartLsr] and UartLsrThrEmpty) == 0:
    discard

  uart[UartThr] = U8(ord(ch) and 0xff)


## Reads a console byte through the SBI fallback path.
proc tryGetFallback*(): int =
  int(sbiGetchar())
