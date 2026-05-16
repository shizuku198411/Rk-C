import ../../arch/riscv64/arch
import ../../lib/mem
import ../../lib/types
import ../mm/paging
import ../task/process


const
  UserCStringMax* = U64(256)
  Sv39UserTop = U64(1) shl 38 # 0x0000004000000000


proc isUserCanocnicalVa(va: U64): bool =
  va < Sv39UserTop


proc rangeWithin(start, size, base, limit: U64): bool =
  if size == U64(0):
    return true
  if start < base:
    return false

  let endExclusive = start + size
  if endExclusive < start:
    return false
  
  endExclusive <= limit


proc isCurrentUserVaRange(userAddr, size: U64): bool =
  if currentProc == nil or not currentProc.user.active:
    return false

  let u = currentProc.user

  let
    imageStart = u.base
    imageEnd = u.base + u.imagePages * PageSize
    stackStart = u.stackTop - u.stackPages * PageSize
    stackEnd = u.stackTop
  
  if rangeWithin(userAddr, size, imageStart, imageEnd):
    return true
  if rangeWithin(userAddr, size, stackStart, stackEnd):
    return true

  false


proc userAccessEnable(): U64 =
  let old = arch.readSstatus()
  arch.writeSstatus(old or SstatusSum)
  old


proc userAccessRestore(old: U64) =
  arch.writeSstatus(old)


proc validateUserRange*(userAddr, size: U64, writable: bool): bool =
  if size == 0:
    return true
  if userAddr == 0 or currentProc == nil or currentProc.rootPageTable == nil:
    return false
  #if userAddr + size - 1 < userAddr:
  #  return false
  let lastAddr = userAddr + size - 1
  if lastAddr < userAddr:
    return false

  # reject non-canonical or high-half addresses before walking page tables.
  if not isUserCanocnicalVa(userAddr) or not isUserCanocnicalVa(lastAddr):
    return false
  # reject addresses outside this process' declared user memory ranges.
  if not isCurrentUserVaRange(userAddr, size):
    return false

  let required =
    if writable:
      PteW
    else:
      PteR

  var cur = alignDown(userAddr, PageSize)
  let last = alignDown(userAddr + size - 1, PageSize)
  while true:
    let flags = mappedPageFlags(currentProc.rootPageTable, cur)
    if (flags and PteU) == 0 or (flags and required) == 0:
      return false
    if cur == last:
      break
    cur += PageSize

  true


proc copyFromUser*(dst: pointer, src: U64, size: U64): int =
  if dst == nil and size > 0:
    return -1
  if not validateUserRange(src, size, false):
    return -1

  let old = userAccessEnable()
  discard copyMem(dst, cast[pointer](src), size)
  userAccessRestore(old)
  0


proc copyToUser*(dst: U64, src: pointer, size: U64): int =
  if src == nil and size > 0:
    return -1
  if not validateUserRange(dst, size, true):
    return -1

  let old = userAccessEnable()
  discard copyMem(cast[pointer](dst), src, size)
  userAccessRestore(old)
  0


proc copyUserCString*(dst: pointer, src: U64, capacity: U64): int =
  if dst == nil or src == 0 or capacity == 0:
    return -1

  let outBuf = cast[ptr UncheckedArray[char]](dst)
  let old = userAccessEnable()
  var i = U64(0)
  while i + 1 < capacity:
    #if not validateUserRange(src + i, 1, false):
    #  userAccessRestore(old)
    #  return -1
    if src + i < src:
      userAccessRestore(old)
      return -1

    let ch = cast[ptr UncheckedArray[char]](src)[i]
    outBuf[i] = ch
    if ch == '\0':
      userAccessRestore(old)
      return int(i)
    inc i

  outBuf[i] = '\0'
  userAccessRestore(old)
  -1
