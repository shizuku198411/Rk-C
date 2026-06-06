## Provides Milk-V Duo 256M static CPU information fallback data.
import ../../lib/fixed_string
import ../../lib/syscall_types
import ../../lib/types
import ./memory_layout


const MilkvMainCpuClockHz = U64(1_000_000_000)


## Fills static CPU information for Milk-V Duo 256M.
proc fillCpuStaticInfo*(info: var SysCpuStaticInfo) =
  info.hartCount = U32(1)
  info.bootHartId = U64(0)
  info.timebaseHz = MilkvTimerFrequency
  info.coreClockHz = MilkvMainCpuClockHz

  discard copyCString(info.platform, cstring("Milk-V Duo 256M"))
  discard copyCString(info.soc, cstring("Sophgo SG2002"))
  discard copyCString(info.cpu, cstring("T-Head C906"))
  discard copyCString(info.isa, cstring("rv64imafdcv"))
  discard copyCString(info.mmu, cstring("sv39"))
