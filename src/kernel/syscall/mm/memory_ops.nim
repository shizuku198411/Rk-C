## Implements memory-management related syscall handlers.
import ../../../lib/syscall_types
import ../../../lib/types
import ../../lib/syscall_out
import ../../mm/memory
import ../../mm/paging
import ../../task/process

when defined(platformMilkVDuo256m):
  import ../../dev/console


## Returns whether heap growth is safe for the current process.
proc heapBreathable(current: ptr Process, newEnd: U64): bool =
  if current == nil or not current.user.active or current.rootPageTable == nil:
    return false

  if newEnd < current.user.heapStart:
    return false

  current.user.heapLimit >= newEnd


## Maps newly requested heap pages and rolls them back if growth fails.
proc growHeapPages(current: ptr Process, startVa, pages: U64): bool =
  var mappedPages = U64(0)

  while mappedPages < pages:
    let pagePa = palloc(U64(1))
    if pagePa == NilPAddr:
      when defined(platformMilkVDuo256m):
        println("[milkv-debug][heap] palloc failed")
      if mappedPages != U64(0):
        discard unmapRangeFree(current.rootPageTable, startVa, mappedPages)
      return false

    let pageVa = startVa + mappedPages * PageSize
    if mapPage(current.rootPageTable, pageVa, pagePa, PteU or PteR or PteW) != 0:
      when defined(platformMilkVDuo256m):
        println("[milkv-debug][heap] map failed")
      discard pfree(pagePa, U64(1))
      if mappedPages != U64(0):
        discard unmapRangeFree(current.rootPageTable, startVa, mappedPages)
      return false

    inc mappedPages

  if mappedPages != U64(0):
    flushTlb()

  true


## Handles the get bit map syscall operation.
proc syscallGetBitMap*(outInfo: U64): U64 =
  if outInfo == 0:
    return U64(-1'i64)

  let info = bitmapInfo()
  var bitmapOut = SysBitmapInfo(total: info.total, used: info.used, free: info.free)
  if not copyOutObject(outInfo, bitmapOut):
    return U64(-1'i64)

  0


## Handles the brk syscall operation.
proc syscallBrk*(newEnd: U64): U64 =
  if currentProc == nil or not currentProc.user.active:
    return U64(-1'i64)

  if newEnd == U64(0):
    return currentProc.user.heapEnd

  if not heapBreathable(currentProc, newEnd):
    when defined(platformMilkVDuo256m):
      println("[milkv-debug][heap] brk rejected")
    return U64(-1'i64)

  let currentPages = heapPageCount(currentProc.user)
  let currentMappedEnd = currentProc.user.heapStart + currentPages * PageSize
  let newPages =
    if newEnd <= currentProc.user.heapStart:
      U64(0)
    else:
      alignUp(newEnd - currentProc.user.heapStart, PageSize) div PageSize

  if newPages > currentPages:
    let growPages = newPages - currentPages
    if not growHeapPages(currentProc, currentMappedEnd, growPages):
      return U64(-1'i64)
  elif newPages < currentPages:
    let shrinkPages = currentPages - newPages
    if unmapRangeFree(currentProc.rootPageTable, currentMappedEnd - shrinkPages * PageSize, shrinkPages) != 0:
      return U64(-1'i64)

  currentProc.user.heapEnd = newEnd
  0


## Handles the sbrk syscall operation.
proc syscallSbrk*(delta: I64): U64 =
  if currentProc == nil or not currentProc.user.active:
    return U64(-1'i64)

  let current = currentProc.user.heapEnd
  var newEnd = current

  if delta >= 0:
    let add = U64(delta)
    if current > high(U64) - add:
      return U64(-1'i64)
    newEnd = current + add
  else:
    if delta == low(I64):
      return U64(-1'i64)

    let sub = U64(-delta)
    if sub > current:
      return U64(-1'i64)
    newEnd = current - sub

  if syscallBrk(newEnd) != 0:
    when defined(platformMilkVDuo256m):
      println("[milkv-debug][heap] sbrk failed")
    return U64(-1'i64)

  current
