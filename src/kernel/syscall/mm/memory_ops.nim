import ../../../lib/syscall_types
import ../../../lib/types
import ../../mm/memory
import ../../mm/usercopy


proc syscallGetBitMap*(outInfo: U64): U64 =
  if outInfo == 0:
    return U64(-1'i64)

  let info = bitmapInfo()
  var bitmapOut = SysBitmapInfo(total: info.total, used: info.used, free: info.free)
  if copyToUser(outInfo, addr bitmapOut, U64(sizeof(SysBitmapInfo))) != 0:
    return U64(-1'i64)

  0
