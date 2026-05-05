import ../../arch/riscv64/arch
import ../../lib/mem
import ../../lib/types
import ../mm/paging
import ../task/process


const
  UserCStringMax* = U64(256)


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
  if userAddr + size - 1 < userAddr:
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
    if not validateUserRange(src + i, 1, false):
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
