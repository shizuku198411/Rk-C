## Stores boot handoff information needed after early initialization.
import ../../lib/types
import ../lib/fdt

var
  bootHartId*: U64
  bootDtb*: pointer
  bootCpuInfo*: FdtCpuInfo


## Records boot handoff values and snapshots FDT CPU data after BSS has been cleared.
proc setBootInfo*(hartid: U64, dtb: pointer) =
  bootHartId = hartid
  bootDtb = dtb
  bootCpuInfo = fdtScanCpuInfo(dtb)
