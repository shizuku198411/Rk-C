## Builds static CPU information from platform backends.
import ../../lib/fixed_string
import ../../lib/syscall_types
import ../../lib/types
import ../../platform/cpu_backend
import ./boot_info


## Returns whether a fixed-size text field contains a non-empty C string.
proc hasText(buf: openArray[char]): bool =
  buf.len > 0 and buf[0] != '\0'


## Copies FDT text into a syscall ABI text field when present.
proc overrideText(dst: var openArray[char], src: openArray[char]) =
  if hasText(src):
    discard copyCString(dst, cast[cstring](unsafeAddr src[0]))


## Overlays FDT CPU information onto platform fallback information.
proc applyFdtCpuInfo(info: var SysCpuStaticInfo) =
  if not bootCpuInfo.valid:
    return

  if bootCpuInfo.hartCount != U32(0):
    info.hartCount = bootCpuInfo.hartCount

  info.bootHartId = bootHartId

  if bootCpuInfo.timebaseHz != U64(0):
    info.timebaseHz = bootCpuInfo.timebaseHz

  if info.coreClockHz == U64(0) and bootCpuInfo.coreClockHz != U64(0):
    info.coreClockHz = bootCpuInfo.coreClockHz

  overrideText(info.platform, bootCpuInfo.model)
  overrideText(info.soc, bootCpuInfo.compatible)
  overrideText(info.cpu, bootCpuInfo.cpuCompatible)
  overrideText(info.isa, bootCpuInfo.isa)
  overrideText(info.mmu, bootCpuInfo.mmuType)


## Returns static CPU information for the current platform.
proc cpuStaticInfo*(): SysCpuStaticInfo =
  result = SysCpuStaticInfo()
  fillCpuStaticInfo(result)
  result.bootHartId = bootHartId
  applyFdtCpuInfo(result)
