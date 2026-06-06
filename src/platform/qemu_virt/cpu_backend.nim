## Provides QEMU virt static CPU information fallback data.
import ../../lib/fixed_string
import ../../lib/syscall_types
import ../../lib/types


## Fills static CPU information for QEMU virt.
proc fillCpuStaticInfo*(info: var SysCpuStaticInfo) =
  info.hartCount = U32(1)
  info.bootHartId = U64(0)
  info.timebaseHz = U64(10_000_000)
  info.coreClockHz = U64(0)

  discard copyCString(info.platform, cstring("QEMU virt"))
  discard copyCString(info.soc, cstring("virt"))
  discard copyCString(info.cpu, cstring("riscv64 generic"))
  discard copyCString(info.isa, cstring("rv64imac"))
  discard copyCString(info.mmu, cstring("sv39"))
