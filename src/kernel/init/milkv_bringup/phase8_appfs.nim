## Runs Milk-V Phase 8 block partition and appfs validation.
import ../../../lib/types
import ../../dev/console
import ../../fs/blockdev
import ../../fs/fs
import ../../fs/partition
import ../../../platform/milkv_duo256m/memory_layout
import ./shared

## Prints a Milk-V partition record.
proc printMilkvPartition(label: cstring, part: BlockPartition) =
  printMilkvPrefix()
  printConsoleOnly(label)
  printConsoleOnly(": type=")
  printHex(U64(part.typ))
  printConsoleOnly(" start=")
  printUnsigned(part.startBlock)
  printConsoleOnly(" blocks=")
  printUnsigned(part.blockCount)
  putChar('\n')


## Runs Phase 8A block/appfs diagnostics without starting the full service tree.
proc runMilkvPhase8AppfsChecks*() =
  printlnConsoleOnly("")
  printlnConsoleOnly("[milkv] phase8 appfs bootstrap checks")

  blockdevInit()

  var part: BlockPartition
  if not readMbrPartition(MilkvAppfsPartitionIndex, part):
    printMilkvStatus("appfs partition", "FAIL")
    return

  printMilkvPartition("  selected partition", part)
  if not blockdevSetLogicalRange(part.startBlock, part.blockCount):
    printMilkvStatus("logical block range", "FAIL")
    return

  fsSetAppfsBaseBlock(MilkvAppfsLocalStartBlock)
  printMilkvHex("  logical base block", blockdevBaseOffset())
  printMilkvHex("  appfs local block", fsAppfsBaseBlock())

  if fsLoadAppfsOnly() != 0:
    printMilkvStatus("appfs load", "FAIL")
    return

  printMilkvStatus("appfs load", "OK")
  printMilkvUnsigned("  appfs entries", U64(fsAppfsEntryCount()))

  let svcmgtdSize = fsAppfsFileSize("/bin/svcmgtd")
  let loginSize = fsAppfsFileSize("/bin/login")
  let shellSize = fsAppfsFileSize("/bin/shell")
  printMilkvUnsigned("  /bin/svcmgtd size", U64(if svcmgtdSize < 0: 0 else: svcmgtdSize))
  printMilkvUnsigned("  /bin/login size", U64(if loginSize < 0: 0 else: loginSize))
  printMilkvUnsigned("  /bin/shell size", U64(if shellSize < 0: 0 else: shellSize))

  if svcmgtdSize >= 0 and loginSize >= 0 and shellSize >= 0:
    printMilkvStatus("appfs lookup", "OK")
    printMilkvStatus("phase8 appfs bootstrap", "OK")
  else:
    printMilkvStatus("appfs lookup", "FAIL")
    printMilkvStatus("phase8 appfs bootstrap", "FAIL")
