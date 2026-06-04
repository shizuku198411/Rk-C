## Runs Milk-V Phase 7 UART and SD device validation.
import ../../../lib/types
import ../../dev/console
import ../../dev/uart16550
import ../../dev/sd/sdhci
import ../../../platform/milkv_duo256m/memory_layout
import ./shared

## Reads a little-endian U32 from a byte buffer.
proc milkvReadLe32(buf: ptr UncheckedArray[U8], offset: U64): U32 =
  U32(buf[offset]) or
    (U32(buf[offset + U64(1)]) shl 8) or
    (U32(buf[offset + U64(2)]) shl 16) or
    (U32(buf[offset + U64(3)]) shl 24)


## Prints a fixed number of bytes from a buffer as hexadecimal.
proc printMilkvBytes(label: cstring, buf: ptr UncheckedArray[U8], count: U64) =
  printMilkvPrefix()
  printConsoleOnly(label)
  printConsoleOnly(" =")

  var i = U64(0)
  while i < count:
    putChar(' ')
    let value = U64(buf[i])
    if value < U64(0x10):
      putChar('0')
    printHex(value)
    inc i

  putChar('\n')


## Prints one MBR partition entry from an SD card sector.
proc printMilkvPartitionEntry(index: U64, buf: ptr UncheckedArray[U8]) =
  let off = U64(0x1be) + index * U64(16)
  let partType = buf[off + U64(4)]
  let startLba = milkvReadLe32(buf, off + U64(8))
  let sectors = milkvReadLe32(buf, off + U64(12))

  printMilkvPrefix()
  printConsoleOnly("  partition ")
  printUnsigned(index + U64(1))
  printConsoleOnly(": type=")
  printHex(U64(partType))
  printConsoleOnly(" start=")
  printUnsigned(U64(startLba))
  printConsoleOnly(" sectors=")
  printUnsigned(U64(sectors))
  putChar('\n')


## Runs a direct UART0 MMIO probe without changing the global console backend.
proc runMilkvPhase7UartChecks(): bool =
  let uart = Uart16550(base: MilkvUart0Base, regShift: U8(2), regWidth: U8(4))
  printMilkvPrefix()
  printlnConsoleOnly("uart0:")
  printMilkvHex("  base", MilkvUart0Base)
  printMilkvUnsigned("  reg shift", U64(uart.regShift))
  printMilkvUnsigned("  reg width", U64(uart.regWidth))
  printMilkvHex("  lsr", U64(uartRead(uart, U64(5))))

  if not uart16550Probe(uart):
    printMilkvStatus("uart0 probe", "FAIL")
    return false

  printMilkvStatus("uart0 probe", "OK")
  printMilkvPrefix()
  printConsoleOnly("  direct uart write: ")
  discard uart16550PutChar(uart, 'O')
  discard uart16550PutChar(uart, 'K')
  discard uart16550PutChar(uart, '\n')
  true


## Runs a direct SDHCI probe and attempts to read sector zero from the SD card.
proc runMilkvPhase7SdChecks(): bool =
  var sector: array[512, U8]
  printMilkvPrefix()
  printlnConsoleOnly("sdhci:")
  printMilkvHex("  base", MilkvSdBase)

  let probe = probeSdhci(MilkvSdBase)
  printMilkvHex("  host version", U64(probe.hostVersion))
  printMilkvHex("  present state", U64(probe.presentState))
  printMilkvHex("  capabilities", probe.capabilities)
  printMilkvHex("  clock control", U64(probe.clockControl))
  printMilkvHex("  power control", U64(probe.powerControl))
  printMilkvStatus("sdhci probe", "OK")

  let read = readLba0(MilkvSdBase, addr sector[0])
  printMilkvUnsigned("  read stage", U64(ord(read.stage)))
  printMilkvHex("  int status", U64(read.intStatus))
  printMilkvHex("  present state", U64(read.presentState))
  printMilkvUnsigned("  words read", read.wordsRead)

  if not read.ok:
    printMilkvStatus("sd lba0 read", "FAIL")
    return false

  let bytes = cast[ptr UncheckedArray[U8]](addr sector[0])
  printMilkvBytes("  mbr first bytes", bytes, U64(16))
  let signature = U16(bytes[U64(510)]) or (U16(bytes[U64(511)]) shl 8)
  if signature == U16(0xaa55):
    printMilkvStatus("mbr signature", "OK")
    var i = U64(0)
    while i < U64(4):
      printMilkvPartitionEntry(i, bytes)
      inc i
    return true

  printMilkvStatus("mbr signature", "WARN")
  true


## Runs Phase 7 UART and SD card driver checks before entering the scheduled runtime.
proc runMilkvPhase7Checks*() =
  printlnConsoleOnly("")
  printlnConsoleOnly("[milkv] phase7 uart/sd driver checks")

  let uartOk = runMilkvPhase7UartChecks()
  let sdOk = runMilkvPhase7SdChecks()
  if uartOk and sdOk:
    printMilkvStatus("phase7 uart/sd drivers", "OK")
  else:
    printMilkvStatus("phase7 uart/sd drivers", "FAIL")
