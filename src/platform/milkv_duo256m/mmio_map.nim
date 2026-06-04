## Maps Milk-V Duo 256M device ranges into a kernel page table.
import ../../kernel/mm/paging
import ../../lib/types
import ./memory_layout


## Maps all kernel-visible Milk-V device MMIO ranges.
proc mapPlatformDeviceRanges*(root: PageTable): int =
  if mapDeviceRange(root, PAddr(MilkvPinmuxBase), PAddr(MilkvPinmuxBase), MilkvDeviceMmioSize, PteR or PteW) != 0:
    return -1

  if mapDeviceRange(root, PAddr(MilkvUart0Base), PAddr(MilkvUart0Base), MilkvDeviceMmioSize, PteR or PteW) != 0:
    return -1

  if mapDeviceRange(root, PAddr(MilkvSdBase), PAddr(MilkvSdBase), MilkvDeviceMmioSize, PteR or PteW) != 0:
    return -1

  if mapDeviceRange(root, PAddr(MilkvGpioEBase), PAddr(MilkvGpioEBase), MilkvGpioESize, PteR or PteW) != 0:
    return -1

  if mapDeviceRange(root, PAddr(MilkvRtcBase), PAddr(MilkvRtcBase), MilkvRtcSize, PteR or PteW) != 0:
    return -1

  0
