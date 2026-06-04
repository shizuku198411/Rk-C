## Runs Milk-V Phase 2 physical memory and allocator validation.
import ../../../lib/types
import ../../dev/console
import ../../mm/memory
import ../../../platform/milkv_duo256m/memory_layout
import ../runtime_setup
import ./shared

## Checks whether an address is inside the early managed memory window.
proc milkvAddressInManagedRange(value: U64): bool =
  value >= MilkvEarlyManagedStart and value < MilkvEarlyManagedEnd


## Checks whether one memory range intersects the early managed memory window.
proc milkvRangeOverlapsManagedRange(start, last: U64): bool =
  start < MilkvEarlyManagedEnd and last > MilkvEarlyManagedStart


## Prints the early memory range candidate for the next bring-up phase.
proc printMilkvMemoryCandidate*(dtb: pointer) =
  printMilkvPrefix()
  printlnConsoleOnly("memory candidate:")
  printMilkvHex("  kernel end", cast[U64](addr kernelEndSym))
  printMilkvHex("  free start", MilkvEarlyManagedStart)
  printMilkvHex("  free end  ", MilkvEarlyManagedEnd)
  printMilkvHex("  fdt       ", cast[U64](dtb))

  let fdtAddr = cast[U64](dtb)
  if milkvAddressInManagedRange(fdtAddr):
    printMilkvStatus("fdt range", "WARN")
  else:
    printMilkvStatus("fdt range", "OK")


## Verifies that the early allocator window is safe for Phase 2 use.
proc validateMilkvMemoryWindow(dtb: pointer): bool =
  let kernelBase = cast[U64](addr kernelBaseSym)
  let kernelEnd = cast[U64](addr kernelEndSym)
  let stackBottom = cast[U64](addr stackBottomSym)
  let stackTop = cast[U64](addr stackTopSym)
  let fdtAddr = cast[U64](dtb)

  printMilkvPrefix()
  printlnConsoleOnly("phase2 memory validation:")

  var ok = true

  if MilkvKernelLoadBase == kernelBase:
    printMilkvStatus("  kernel load base", "OK")
  else:
    printMilkvStatus("  kernel load base", "FAIL")
    ok = false

  if MilkvEarlyManagedStart < MilkvEarlyManagedEnd:
    printMilkvStatus("  managed range order", "OK")
  else:
    printMilkvStatus("  managed range order", "FAIL")
    ok = false

  if kernelEnd <= MilkvEarlyManagedStart:
    printMilkvStatus("  kernel outside managed", "OK")
  else:
    printMilkvStatus("  kernel outside managed", "FAIL")
    ok = false

  if not milkvRangeOverlapsManagedRange(stackBottom, stackTop):
    printMilkvStatus("  stack outside managed", "OK")
  else:
    printMilkvStatus("  stack outside managed", "FAIL")
    ok = false

  if not milkvAddressInManagedRange(fdtAddr):
    printMilkvStatus("  fdt outside managed", "OK")
  else:
    printMilkvStatus("  fdt outside managed", "FAIL")
    ok = false

  if MilkvEarlyManagedEnd <= MilkvReservedIonStart:
    printMilkvStatus("  reserved ion outside managed", "OK")
  else:
    printMilkvStatus("  reserved ion outside managed", "FAIL")
    ok = false

  if fdtAddr == MilkvKnownFdtAddr:
    printMilkvStatus("  known fdt address", "OK")
  else:
    printMilkvStatus("  known fdt address", "WARN")

  ok


## Initializes the physical allocator with the validated Milk-V early range.
proc initMilkvPhase2Memory(): MemoryInfo =
  let memInfo = initMemoryAllocator(MilkvEarlyManagedStart, MilkvEarlyManagedEnd)
  printMilkvPrefix()
  printlnConsoleOnly("allocator:")
  printMilkvHex("  bitmap start", memInfo.freeRamStart)
  printMilkvUnsigned("  bitmap pages", memInfo.bitmapPageCount)
  printMilkvHex("  managed start", memInfo.managedRegionStart)
  printMilkvUnsigned("  managed pages", memInfo.managedPageCount)
  memInfo


## Exercises palloc/pfree once so real hardware can validate allocator basics.
proc runMilkvAllocatorSmokeTest() =
  let before = bitmapInfo()
  printMilkvPrefix()
  printlnConsoleOnly("allocator smoke:")
  printMilkvUnsigned("  total pages before", before.total)
  printMilkvUnsigned("  used pages before ", before.used)
  printMilkvUnsigned("  free pages before ", before.free)

  let pageA = palloc(U64(1))
  let pageB = palloc(U64(1))
  printMilkvHex("  page A", pageA)
  printMilkvHex("  page B", pageB)

  if pageA == NilPAddr or pageB == NilPAddr or pageA == pageB:
    printMilkvStatus("  allocate pages", "FAIL")
    return

  cast[ptr U64](pageA)[] = U64(0x1122334455667788)
  cast[ptr U64](pageB)[] = U64(0x8877665544332211)

  let afterAlloc = bitmapInfo()
  if afterAlloc.used == before.used + U64(2):
    printMilkvStatus("  allocation accounting", "OK")
  else:
    printMilkvStatus("  allocation accounting", "FAIL")

  let freeA = pfree(pageA, U64(1))
  let freeB = pfree(pageB, U64(1))
  if freeA == 0 and freeB == 0:
    printMilkvStatus("  free pages", "OK")
  else:
    printMilkvStatus("  free pages", "FAIL")

  let afterFree = bitmapInfo()
  printMilkvUnsigned("  used pages after  ", afterFree.used)
  printMilkvUnsigned("  free pages after  ", afterFree.free)

  if afterFree.used == before.used and afterFree.free == before.free:
    printMilkvStatus("  free accounting", "OK")
  else:
    printMilkvStatus("  free accounting", "FAIL")


## Runs Phase 2 memory runtime checks and allocator smoke tests.
proc runMilkvPhase2Checks*(dtb: pointer) =
  printlnConsoleOnly("")
  printlnConsoleOnly("[milkv] phase2 memory runtime checks")
  if not validateMilkvMemoryWindow(dtb):
    printMilkvStatus("phase2 memory validation", "FAIL")
    return

  discard initMilkvPhase2Memory()
  runMilkvAllocatorSmokeTest()
  printMilkvStatus("phase2 memory runtime", "OK")
