## Provides Milk-V Duo 256M console I/O backend routines.
import ../../kernel/dev/uart16550
import ../../lib/types
import ./memory_layout


## Imports the SBI getchar routine used as a fallback.
proc sbiGetchar(): clong {.importc: "sbi_getchar", cdecl.}


## Imports the SBI putchar routine used for stable early console output.
proc sbiPutchar(ch: clong) {.importc: "sbi_putchar", cdecl.}


## Returns the Milk-V UART used for console input.
proc consoleUart(): Uart16550 =
  Uart16550(base: MilkvUart0Base, regShift: U8(2), regWidth: U8(4))


## Polls the Milk-V UART and pushes all available input bytes.
proc pollInput*(push: proc(ch: char): bool): bool =
  let uart = consoleUart()
  var pushed = false

  while true:
    let ch = uart16550TryGetChar(uart)
    if ch < 0:
      break

    if not push(char(ch and 0xff)):
      break
    pushed = true

  pushed


## Writes one byte through SBI console output.
proc putChar*(ch: char) =
  sbiPutchar(clong(ord(ch) and 0xff))


## Reads a console byte through the SBI fallback path.
proc tryGetFallback*(): int =
  int(sbiGetchar())
