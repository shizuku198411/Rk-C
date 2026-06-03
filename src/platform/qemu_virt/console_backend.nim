## Provides QEMU virt console I/O backend routines.
import ../../lib/types
import ./memory_layout

const
  UartRbr = U64(0)
  UartThr = U64(0)
  UartLsr = U64(5)
  UartLsrDataReady = U8(1 shl 0)
  UartLsrThrEmpty = U8(1 shl 5)


## Imports the SBI getchar routine used as a fallback.
proc sbiGetchar(): clong {.importc: "sbi_getchar", cdecl.}


## Polls the QEMU UART and pushes all available input bytes.
proc pollInput*(push: proc(ch: char): bool): bool =
  let uart = cast[ptr UncheckedArray[U8]](QemuUart0Base)
  var pushed = false

  while (uart[UartLsr] and UartLsrDataReady) != 0:
    if not push(char(uart[UartRbr])):
      discard uart[UartRbr]
      break
    pushed = true

  pushed


## Writes one byte directly to the QEMU emulated 16550 UART.
proc putChar*(ch: char) =
  let uart = cast[ptr UncheckedArray[U8]](QemuUart0Base)

  while (uart[UartLsr] and UartLsrThrEmpty) == 0:
    discard

  uart[UartThr] = U8(ord(ch) and 0xff)


## Reads a console byte through the SBI fallback path.
proc tryGetFallback*(): int =
  int(sbiGetchar())
