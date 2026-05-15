import ../../../lib/syscall_types
import ../../../lib/types
import ../../lib/syscall_out
import ../../mm/memory


proc syscallGetBitMap*(outInfo: U64): U64 =
  if outInfo == 0:
    return U64(-1'i64)

  let info = bitmapInfo()
  var bitmapOut = SysBitmapInfo(total: info.total, used: info.used, free: info.free)
  if not copyOutObject(outInfo, bitmapOut):
    return U64(-1'i64)

  0
