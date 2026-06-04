## Runs Milk-V Phase 4 device tree validation.
import ../../../lib/types
import ../../dev/console
import ../../lib/fdt
import ../../../platform/milkv_duo256m/memory_layout
import ./shared

## Prints one parsed FDT region.
proc printMilkvFdtRegion(prefix: cstring, region: FdtRegion) =
  printMilkvPrefix()
  printConsoleOnly(prefix)
  printConsoleOnly(" ")
  var i = 0
  while i < region.name.len and region.name[i] != '\0':
    putChar(region.name[i])
    inc i
  printConsoleOnly(" base=")
  printPtr(region.base)
  printConsoleOnly(" size=")
  printPtr(region.size)
  putChar('\n')


## Prints FDT parser header diagnostics.
proc printMilkvFdtHeader(scan: FdtScanResult) =
  printMilkvPrefix()
  printlnConsoleOnly("fdt header:")
  printMilkvHex("  magic     ", U64(scan.header.magic))
  printMilkvHex("  totalsize ", scan.header.totalSize)
  printMilkvHex("  struct off", scan.header.offDtStruct)
  printMilkvHex("  strings off", scan.header.offDtStrings)
  printMilkvHex("  reserve off", scan.header.offMemRsvmap)
  printMilkvHex("  struct size", scan.header.sizeDtStruct)
  printMilkvHex("  strings size", scan.header.sizeDtStrings)
  printMilkvUnsigned("  version   ", U64(scan.header.version))
  printMilkvUnsigned("  last comp ", U64(scan.header.lastCompVersion))


## Prints FDT memory and reserved memory diagnostics.
proc printMilkvFdtMemory(scan: FdtScanResult) =
  printMilkvPrefix()
  printlnConsoleOnly("memory:")
  printMilkvUnsigned("  address-cells", U64(scan.addressCells))
  printMilkvUnsigned("  size-cells   ", U64(scan.sizeCells))
  if scan.memoryRegion.valid:
    printMilkvFdtRegion("  memory", scan.memoryRegion)
    printMilkvStatus("memory range", "OK")
  else:
    printMilkvStatus("memory range", "WARN")

  printMilkvPrefix()
  printlnConsoleOnly("fdt reserve map:")
  if scan.reserveMapCount == U64(0):
    printMilkvStatus("  reserve map", "empty")
  else:
    var i = U64(0)
    while i < scan.reserveMapCount:
      printMilkvFdtRegion("  reserve", scan.reserveMap[i])
      inc i

  printMilkvPrefix()
  printlnConsoleOnly("reserved-memory:")
  if scan.reservedMemoryCount == U64(0):
    printMilkvStatus("  reserved-memory", "WARN")
  else:
    var i = U64(0)
    while i < scan.reservedMemoryCount:
      printMilkvFdtRegion("  region", scan.reservedMemory[i])
      inc i


## Prints FDT device candidate diagnostics.
proc printMilkvDeviceCandidate(label: cstring, found: bool) =
  if found:
    printMilkvStatus(label, "FOUND")
  else:
    printMilkvStatus(label, "MISSING")


## Returns whether one reserved-memory range matches the known ION base.
proc fdtHasKnownIonRegion(scan: FdtScanResult): bool =
  var i = U64(0)
  while i < scan.reservedMemoryCount:
    if scan.reservedMemory[i].valid and scan.reservedMemory[i].base == MilkvReservedIonStart:
      return true
    inc i

  false


## Prints DTB values against Milk-V fixed fallback values.
proc printMilkvPlatformCompare(dtb: pointer, scan: FdtScanResult) =
  printMilkvPrefix()
  printlnConsoleOnly("platform compare:")

  if cast[U64](dtb) == MilkvKnownFdtAddr:
    printMilkvStatus("  fdt pointer", "OK")
  else:
    printMilkvStatus("  fdt pointer", "WARN")

  if scan.uart0Found:
    printMilkvStatus("  uart0 base", "OK")
  else:
    printMilkvStatus("  uart0 base", "WARN")

  if fdtHasKnownIonRegion(scan):
    printMilkvStatus("  ion base", "OK")
  else:
    printMilkvStatus("  ion base", "WARN")


## Runs Phase 4 FDT/DTB parser checks.
proc runMilkvPhase4Checks*(dtb: pointer) =
  printlnConsoleOnly("")
  printlnConsoleOnly("[milkv] phase4 dtb runtime checks")

  let scan = fdtScanBasic(dtb)
  printMilkvFdtHeader(scan)

  if not scan.header.valid:
    printMilkvStatus("fdt header", "FAIL")
    printMilkvStatus("platform fallback", "OK")
    return

  printMilkvStatus("fdt header", "OK")
  if scan.scanOk:
    printMilkvStatus("fdt structure scan", "OK")
  else:
    printMilkvStatus("fdt structure scan", "WARN")

  printMilkvPrefix()
  printlnConsoleOnly("chosen:")
  printMilkvFixedString("  stdout-path", scan.stdoutPath)

  printMilkvFdtMemory(scan)

  printMilkvPrefix()
  printlnConsoleOnly("device candidates:")
  printMilkvDeviceCandidate("  uart0 serial@4140000", scan.uart0Found)
  printMilkvDeviceCandidate("  plic interrupt-controller@70000000", scan.plicFound)
  printMilkvDeviceCandidate("  clint", scan.clintFound)
  printMilkvDeviceCandidate("  sd cv-sd@4310000", scan.sdFound)
  printMilkvDeviceCandidate("  ethernet@4070000", scan.ethernetFound)
  printMilkvPlatformCompare(dtb, scan)
  printMilkvStatus("phase4 dtb runtime", "OK")
