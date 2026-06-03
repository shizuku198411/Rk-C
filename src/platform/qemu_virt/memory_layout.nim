## Defines QEMU virt physical device layout constants.
import ../../lib/types

const
  QemuBlockCount* = U64(32768)
  QemuUart0Base* = U64(0x10000000)
  QemuMmioSize* = U64(0x00010000)
  QemuPlicBase* = U64(0x0c000000)
  QemuPlicSize* = U64(0x00400000)
  QemuRtcBase* = U64(0x00101000)
  QemuRtcSize* = U64(0x00001000)
