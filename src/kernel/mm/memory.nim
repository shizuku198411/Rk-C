import ../../lib/mem
import ../../lib/types
import ../dev/console

type
  MemoryInfo* = object
    freeRamStart*: PAddr
    managedRegionStart*: PAddr
    bitmapPageCount*: U64
    managedPageCount*: U64

var
  freeRamStartSym {.importc: "__free_ram_start".}: char
  freeRamEndSym {.importc: "__free_ram_end".}: char
  bitmap: ptr UncheckedArray[U8]
  managedRegionStart: PAddr
  managedPageCount: U64
  bitmapPageCount: U64
  memoryInitialized: bool

func calcTotalPage(start, last: PAddr): U64 =
  (last - start) div PageSize

func calcBitmapBytes(pageCount: U64): U64 =
  (pageCount + 7'u64) div 8'u64

func calcBitmapPageCount(pageCount: U64): U64 =
  alignUp(calcBitmapBytes(pageCount), PageSize) div PageSize


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

  memoryInitialized = true

  MemoryInfo(
    freeRamStart: freeStart,
    managedRegionStart: managedRegionStart,
    bitmapPageCount: bitmapPageCount,
    managedPageCount: managedPageCount,
  )


proc memoryInit*(): MemoryInfo =
  initMemoryAllocator(
    cast[PAddr](addr freeRamStartSym),
    cast[PAddr](addr freeRamEndSym),
  )


proc bitmapCheck(idx: U64): bool =
  ((bitmap[idx div 8] shr (idx mod 8)) and 1'u8) != 0


proc bitmapSet(idx: U64) =
  bitmap[idx div 8] = bitmap[idx div 8] or U8(1'u8 shl (idx mod 8))


proc bitmapClear(idx: U64) =
  bitmap[idx div 8] = bitmap[idx div 8] and not U8(1'u8 shl (idx mod 8))


proc palloc*(n: U64): PAddr =
  if not memoryInitialized:
    panic("memory allocator is not initialized")
  if n == 0 or n > managedPageCount:
    return NilPAddr

  var run = U64(0)
  var i = U64(0)
  while i < managedPageCount:
    if bitmapCheck(i):
      run = 0
      inc i
      continue

    inc run
    if run == n:
      let start = i + 1'u64 - n
      var j = start
      while j <= i:
        bitmapSet(j)
        inc j

      let paddr = managedRegionStart + start * PageSize
      zeroMem(cast[pointer](paddr), n * PageSize)
      return paddr

    inc i

  NilPAddr


proc pfree*(paddr: PAddr, n: U64): int =
  if not memoryInitialized:
    panic("memory allocator is not initialized")
  if not isAligned(paddr, PageSize):
    panic("unaligned target address")
  if n == 0 or n > managedPageCount:
    return -1
  if paddr < managedRegionStart:
    return -1

  let start = (paddr - managedRegionStart) div PageSize
  if start >= managedPageCount or start + n > managedPageCount:
    return -1

  var i = U64(0)
  while i < n:
    if not bitmapCheck(start + i):
      return -1
    inc i

  zeroMem(cast[pointer](paddr), n * PageSize)

  i = 0
  while i < n:
    bitmapClear(start + i)
    inc i

  0
