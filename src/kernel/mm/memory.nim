## Implements the physical page allocator and bitmap accounting.
import ../../lib/mem
import ../../lib/types
import ../dev/console

type
  MemoryInfo* = object
    freeRamStart*: PAddr
    managedRegionStart*: PAddr
    bitmapPageCount*: U64
    managedPageCount*: U64

  BitmapInfo* = object
    total*: U64
    used*: U64
    free*: U64

var
  freeRamStartSym {.importc: "__free_ram_start".}: char
  freeRamEndSym {.importc: "__free_ram_end".}: char
  bitmap: ptr UncheckedArray[U8]
  managedRegionStart: PAddr
  managedPageCount: U64
  bitmapPageCount: U64
  memoryInitialized: bool

  ## Number of pages currently marked as allocated in the managed region.
  ##
  ## This lets bitmapInfo() avoid scanning the whole bitmap every time.
  usedPageCount: U64

  ## Next page index to start allocation search from.
  ##
  ## This avoids repeatedly scanning from page 0 for every palloc().
  nextFreeHint: U64


## Calculates total page.
func calcTotalPage(start, last: PAddr): U64 =
  (last - start) div PageSize


## Calculates bitmap bytes.
func calcBitmapBytes(pageCount: U64): U64 =
  (pageCount + 7'u64) div 8'u64


## Calculates bitmap page count.
func calcBitmapPageCount(pageCount: U64): U64 =
  alignUp(calcBitmapBytes(pageCount), PageSize) div PageSize


## Implements the bitmap check kernel helper.
proc bitmapCheck(idx: U64): bool =
  ((bitmap[idx div 8] shr (idx mod 8)) and 1'u8) != 0


## Implements the bitmap set kernel helper.
proc bitmapSet(idx: U64) =
  bitmap[idx div 8] = bitmap[idx div 8] or U8(1'u8 shl (idx mod 8))


## Implements the bitmap clear kernel helper.
proc bitmapClear(idx: U64) =
  bitmap[idx div 8] = bitmap[idx div 8] and not U8(1'u8 shl (idx mod 8))


## Marks one managed page as used and updates allocator accounting.
proc markPageUsed(idx: U64) =
  if idx >= managedPageCount:
    return

  if not bitmapCheck(idx):
    bitmapSet(idx)
    inc usedPageCount


## Marks one managed page as free and updates allocator accounting.
proc markPageFree(idx: U64) =
  if idx >= managedPageCount:
    return

  if bitmapCheck(idx):
    bitmapClear(idx)
    if usedPageCount > U64(0):
      dec usedPageCount


## Recomputes allocator accounting from the bitmap.
##
## This is mainly useful after initialization or while debugging allocator state.
proc recomputeUsedPageCount*() =
  if not memoryInitialized:
    return

  var used = U64(0)
  var i = U64(0)

  while i < managedPageCount:
    if bitmapCheck(i):
      inc used
    inc i

  usedPageCount = used

  if usedPageCount >= managedPageCount:
    nextFreeHint = managedPageCount
  elif nextFreeHint >= managedPageCount:
    nextFreeHint = U64(0)


## Initializes memory allocator.
proc initMemoryAllocator*(start, last: PAddr): MemoryInfo =
  let freeStart = alignUp(start, PageSize)
  let freeEnd = alignDown(last, PageSize)

  if freeEnd <= freeStart:
    panic("invalid free ram range")

  let totalPages = calcTotalPage(freeStart, freeEnd)
  if totalPages == 0:
    panic("no allocatable pages")

  var newManagedPages = totalPages
  while true:
    managedPageCount = newManagedPages
    bitmapPageCount = calcBitmapPageCount(managedPageCount)
    if bitmapPageCount >= totalPages:
      panic("bitmap too large for free ram")

    newManagedPages = totalPages - bitmapPageCount
    if newManagedPages == managedPageCount:
      break

  bitmap = cast[ptr UncheckedArray[U8]](freeStart)
  zeroMem(cast[pointer](freeStart), bitmapPageCount * PageSize)

  managedRegionStart = freeStart + bitmapPageCount * PageSize
  managedPageCount = totalPages - bitmapPageCount

  if managedPageCount == 0:
    panic("no managed pages after bitmap allocation")

  usedPageCount = U64(0)
  nextFreeHint = U64(0)
  memoryInitialized = true

  MemoryInfo(
    freeRamStart: freeStart,
    managedRegionStart: managedRegionStart,
    bitmapPageCount: bitmapPageCount,
    managedPageCount: managedPageCount,
  )


## Implements the memory init kernel helper.
proc memoryInit*(): MemoryInfo =
  initMemoryAllocator(
    cast[PAddr](addr freeRamStartSym),
    cast[PAddr](addr freeRamEndSym),
  )


## Finds one free page starting from nextFreeHint.
proc findOneFreePage(): U64 =
  if usedPageCount >= managedPageCount:
    return managedPageCount

  var start = nextFreeHint
  if start >= managedPageCount:
    start = U64(0)

  var i = start
  while i < managedPageCount:
    if not bitmapCheck(i):
      return i
    inc i

  i = U64(0)
  while i < start:
    if not bitmapCheck(i):
      return i
    inc i

  managedPageCount


## Finds a contiguous free run in [start, managedPageCount).
proc findFreeRunFrom(start, n: U64): U64 =
  if n == U64(0) or n > managedPageCount:
    return managedPageCount

  if start >= managedPageCount:
    return managedPageCount

  var i = start
  var runStart = start
  var runLen = U64(0)

  while i < managedPageCount:
    if not bitmapCheck(i):
      if runLen == U64(0):
        runStart = i

      inc runLen

      if runLen == n:
        return runStart
    else:
      runLen = U64(0)

    inc i

  managedPageCount


## Finds a contiguous free run, using nextFreeHint as the first search point.
##
## The search wraps back to 0, but never returns a run that crosses the physical
## end of the managed region.
proc findFreeRun(n: U64): U64 =
  var start = nextFreeHint
  if start >= managedPageCount:
    start = U64(0)

  var found = findFreeRunFrom(start, n)
  if found != managedPageCount:
    return found

  if start > U64(0):
    found = findFreeRunFrom(U64(0), n)
    if found != managedPageCount:
      return found

  managedPageCount


## Moves the allocation hint to the first page after an allocated run.
proc updateNextFreeHintAfterAlloc(start, n: U64) =
  nextFreeHint = start + n
  if nextFreeHint >= managedPageCount:
    nextFreeHint = U64(0)


## Allocates physical pages without zeroing them.
##
## Use this only when the caller will immediately overwrite the full allocated
## range before exposing it to user space or interpreting it as page tables.
proc pallocNoZero*(n: U64): PAddr =
  if not memoryInitialized:
    panic("memory allocator is not initialized")

  if n == U64(0) or n > managedPageCount:
    return NilPAddr

  if usedPageCount > managedPageCount:
    return NilPAddr

  if n > managedPageCount - usedPageCount:
    return NilPAddr

  if n == U64(1):
    let idx = findOneFreePage()
    if idx == managedPageCount:
      return NilPAddr

    markPageUsed(idx)
    updateNextFreeHintAfterAlloc(idx, U64(1))

    return managedRegionStart + idx * PageSize

  let start = findFreeRun(n)
  if start == managedPageCount:
    return NilPAddr

  var i = U64(0)
  while i < n:
    markPageUsed(start + i)
    inc i

  updateNextFreeHintAfterAlloc(start, n)

  managedRegionStart + start * PageSize


## Implements the palloc kernel helper.
##
## Existing callers keep the old behavior: allocated pages are zero-filled.
proc palloc*(n: U64): PAddr =
  let paddr = pallocNoZero(n)
  if paddr == NilPAddr:
    return NilPAddr

  zeroMem(cast[pointer](paddr), n * PageSize)
  paddr


## Implements the pfree kernel helper.
proc pfree*(paddr: PAddr, n: U64): int =
  if not memoryInitialized:
    panic("memory allocator is not initialized")

  if not isAligned(paddr, PageSize):
    panic("unaligned target address")

  if n == U64(0) or n > managedPageCount:
    return -1

  if paddr < managedRegionStart:
    return -1

  let start = (paddr - managedRegionStart) div PageSize
  if start >= managedPageCount or n > managedPageCount - start:
    return -1

  var i = U64(0)
  while i < n:
    if not bitmapCheck(start + i):
      return -1
    inc i

  ##
  ## Keep the old behavior: clear memory before returning pages to the allocator.
  ## This is conservative and avoids leaking stale contents if the page is later
  ## reused for user-visible memory.
  ##
  zeroMem(cast[pointer](paddr), n * PageSize)

  i = U64(0)
  while i < n:
    markPageFree(start + i)
    inc i

  if start < nextFreeHint or nextFreeHint >= managedPageCount:
    nextFreeHint = start

  0


## Implements the bitmap info kernel helper.
proc bitmapInfo*(): BitmapInfo =
  if not memoryInitialized:
    panic("memory allocator is not initialized")

  var freePages = U64(0)
  if usedPageCount <= managedPageCount:
    freePages = managedPageCount - usedPageCount

  BitmapInfo(
    total: managedPageCount,
    used: usedPageCount,
    free: freePages,
  )


## Returns the current allocator search hint.
##
## Useful for temporary debugging or exposing allocator stats through procfs.
proc allocatorNextFreeHint*(): U64 =
  nextFreeHint