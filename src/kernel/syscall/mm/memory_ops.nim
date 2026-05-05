import ../../../lib/syscall_types
import ../../../lib/types
import ../../mm/memory


proc syscallGetBitMap*(outInfo: U64): U64 =
  if outInfo == 0:
    return U64(-1'i64)

  let info = bitmapInfo()
  let dst = cast[ptr SysBitmapInfo](outInfo)
  dst.total = info.total
  dst.used = info.used
  dst.free = info.free
  0
