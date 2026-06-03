## Maps QEMU virt device ranges into a kernel page table.
import ../../kernel/mm/paging
import ../../lib/types
import ./memory_layout


## Maps all kernel-visible QEMU device MMIO ranges.
proc mapPlatformDeviceRanges*(root: PageTable): int =
  if mapDeviceRange(root, PAddr(QemuUart0Base), PAddr(QemuUart0Base), QemuMmioSize, PteR or PteW) != 0:
    return -1

  if mapDeviceRange(root, PAddr(QemuPlicBase), PAddr(QemuPlicBase), QemuPlicSize, PteR or PteW) != 0:
    return -1

  if mapDeviceRange(root, PAddr(QemuRtcBase), PAddr(QemuRtcBase), QemuRtcSize, PteR or PteW) != 0:
    return -1

  0
