## Validates user address ranges and copies data across user/kernel memory.
import ../../arch/riscv64/arch
import ../../lib/mem
import ../../lib/types
import ../../lib/calc
import ../mm/paging
import ../task/process


const
  UserCStringMax* = U64(256)
  Sv39UserTop = U64(1) shl 38 # 0x0000004000000000


## Returns whether user canocnical va is true.
proc isUserCanocnicalVa(va: U64): bool =
  va < Sv39UserTop


## Checks or computes the within range.
proc rangeWithin(start, size, base, limit: U64): bool =
  if size == U64(0):
    return true
  if start < base:
    return false

  let endExclusive = start + size
  if endExclusive < start:
    return false
  
  endExclusive <= limit


## Returns whether current user va range is true.
proc isCurrentUserVaRange(userAddr, size: U64): bool =
  if currentProc == nil or not currentProc.user.active:
    return false

  let u = currentProc.user

  let
    imageStart = u.base
    imageEnd = u.base + u.imagePages * PageSize
    stackStart = u.stackTop - u.stackPages * PageSize
    stackEnd = u.stackTop
    heapStart = u.heapStart
    heapEnd = u.heapEnd
  
  if rangeWithin(userAddr, size, imageStart, imageEnd):
    return true
  if rangeWithin(userAddr, size, stackStart, stackEnd):
    return true
  if rangeWithin(userAddr, size, heapStart, heapEnd):
    return true

  false


## Implements the page remaining kernel helper.
proc pageRemaining(va: U64): U64 = 
  PageSize - (va and (PageSize - U64(1)))


## Implements the user access enable kernel helper.
proc userAccessEnable(): U64 =
  let old = arch.readSstatus()
  arch.writeSstatus(old or SstatusSum)
  old


## Implements the user access restore kernel helper.
proc userAccessRestore(old: U64) =
  arch.writeSstatus(old)


## Returns whether validate user range is valid.
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


## Copies from user.
proc copyFromUser*(dst: pointer, src: U64, size: U64): int =
  if dst == nil and size > 0:
    return -1
  if not validateUserRange(src, size, false):
    return -1

  let old = userAccessEnable()
  discard copyMem(dst, cast[pointer](src), size)
  userAccessRestore(old)
  0


## Copies to user.
proc copyToUser*(dst: U64, src: pointer, size: U64): int =
  if src == nil and size > 0:
    return -1
  if not validateUserRange(dst, size, true):
    return -1

  let old = userAccessEnable()
  discard copyMem(cast[pointer](dst), src, size)
  userAccessRestore(old)
  0


## Copies cstring chunk.
proc copyCStringChunk(
  dst: ptr UncheckedArray[char],
  src: U64,
  dstOff: U64,
  chunk: U64,
  copiedEnd: var U64
): bool =
  let old = userAccessEnable()

  var j = 0.U64
  while j < chunk:
    let ch = cast[ptr char](src + j)[]
    dst[dstOff + j] = ch

    if ch == '\0':
      copiedEnd = dstOff + j
      userAccessRestore(old)
      return true

    j += 1.U64

  userAccessRestore(old)
  false


## Copies user cstring.
proc copyUserCString*(dst: pointer, src: U64, capacity: U64): int =
  if dst == nil or src == 0.U64 or capacity == 0.U64:
    return -1

  let d = cast[ptr UncheckedArray[char]](dst)
  var copied = 0.U64

  while copied < capacity - 1.U64:
    let cur = src + copied
    if cur < src:
      return -1

    let remainDst = (capacity - 1.U64) - copied
    let chunk = minU64(remainDst, pageRemaining(cur))

    if not validateUserRange(cur, chunk, false):
      return -1

    var copiedEnd = 0.U64
    if copyCStringChunk(d, cur, copied, chunk, copiedEnd):
      return int(copiedEnd)

    copied += chunk

  d[copied] = '\0'
  -1