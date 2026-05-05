import ../../arch/riscv64/arch
import ../../lib/types
import ../mm/memory

type
  Pte* = U64
  PageTable* = ptr UncheckedArray[Pte]

const
  PageShift* = U64(12)
  VpnMask = U64(0x1ff)
  PteV* = U64(1 shl 0)
  PteR* = U64(1 shl 1)
  PteW* = U64(1 shl 2)
  PteX* = U64(1 shl 3)
  PteU* = U64(1 shl 4)
  PteA* = U64(1 shl 6)
  PteD* = U64(1 shl 7)
  SatpModeSv39* = U64(8) shl 60

func sv39Vpn0(va: VAddr): U64 {.inline.} = (va shr 12) and VpnMask
func sv39Vpn1(va: VAddr): U64 {.inline.} = (va shr 21) and VpnMask
func sv39Vpn2(va: VAddr): U64 {.inline.} = (va shr 30) and VpnMask
func pteIsValid(pte: Pte): bool {.inline.} = (pte and PteV) != 0
func pteIsLeaf(pte: Pte): bool {.inline.} = (pte and (PteR or PteW or PteX)) != 0
func pteToPa(pte: Pte): PAddr {.inline.} = (pte shr 10) shl PageShift
func paToPte(pa: PAddr): Pte {.inline.} = (pa shr PageShift) shl 10


proc allocPageTable*(): PageTable =
  let pa = palloc(1)
  if pa == NilPAddr:
    return nil
  cast[PageTable](pa)


proc walkPageTable*(root: PageTable, va: VAddr, create: bool): ptr Pte =
  let indexes = [sv39Vpn0(va), sv39Vpn1(va), sv39Vpn2(va)]
  var table = root
  var level = 2

  while level > 0:
    let entry = addr table[indexes[level]]
    if pteIsValid(entry[]):
      if pteIsLeaf(entry[]):
        return nil
      table = cast[PageTable](pteToPa(entry[]))
    else:
      if not create:
        return nil

      let next = allocPageTable()
      if next == nil:
        return nil

      entry[] = paToPte(cast[PAddr](next)) or PteV
      table = next

    dec level

  addr table[indexes[0]]


proc mapPage*(root: PageTable, va: VAddr, pa: PAddr, flags: U64): int =
  if not isAligned(va, PageSize) or not isAligned(pa, PageSize):
    return -1

  let entry = walkPageTable(root, va, true)
  if entry == nil:
    return -1

  if pteIsValid(entry[]):
    return -1

  entry[] = paToPte(pa) or flags or PteV or PteA or PteD
  0


proc mapPageReplace*(root: PageTable, va: VAddr, pa: PAddr, flags: U64): int =
  if not isAligned(va, PageSize) or not isAligned(pa, PageSize):
    return -1

  let entry = walkPageTable(root, va, true)
  if entry == nil:
    return -1

  entry[] = paToPte(pa) or flags or PteV or PteA or PteD
  0


proc mapPageReplaceFree*(root: PageTable, va: VAddr, pa: PAddr, flags: U64): int =
  if not isAligned(va, PageSize) or not isAligned(pa, PageSize):
    return -1

  let entry = walkPageTable(root, va, true)
  if entry == nil:
    return -1

  if pteIsValid(entry[]) and pteIsLeaf(entry[]):
    discard pfree(pteToPa(entry[]), 1)

  entry[] = paToPte(pa) or flags or PteV or PteA or PteD
  0


proc mapRange*(root: PageTable, va: VAddr, pa: PAddr, size: Size, flags: U64): int =
  if size == 0:
    return 0

  let alignedSize = alignUp(size, PageSize)
  var off = U64(0)
  while off < alignedSize:
    if mapPage(root, va + off, pa + off, flags) != 0:
      return -1
    off += PageSize

  0


proc mapRangeReplace*(root: PageTable, va: VAddr, pa: PAddr, size: Size, flags: U64): int =
  if size == 0:
    return 0

  let alignedSize = alignUp(size, PageSize)
  var off = U64(0)
  while off < alignedSize:
    if mapPageReplace(root, va + off, pa + off, flags) != 0:
      return -1
    off += PageSize

  0


proc mapRangeReplaceFree*(root: PageTable, va: VAddr, pa: PAddr, size: Size, flags: U64): int =
  if size == 0:
    return 0

  let alignedSize = alignUp(size, PageSize)
  var off = U64(0)
  while off < alignedSize:
    if mapPageReplaceFree(root, va + off, pa + off, flags) != 0:
      return -1
    off += PageSize

  0


proc mappedPagePa*(root: PageTable, va: VAddr): PAddr =
  let entry = walkPageTable(root, alignDown(va, PageSize), false)
  if entry == nil or not pteIsValid(entry[]) or not pteIsLeaf(entry[]):
    return NilPAddr

  pteToPa(entry[])


proc mappedPageFlags*(root: PageTable, va: VAddr): U64 =
  let entry = walkPageTable(root, alignDown(va, PageSize), false)
  if entry == nil or not pteIsValid(entry[]) or not pteIsLeaf(entry[]):
    return 0

  entry[] and 0x3ff'u64


proc unmapRangeFree*(root: PageTable, va: VAddr, pages: U64): int =
  if root == nil:
    return -1
  if va == 0 or pages == 0:
    return 0

  var page = U64(0)
  while page < pages:
    let entry = walkPageTable(root, va + page * PageSize, false)
    if entry != nil and pteIsValid(entry[]) and pteIsLeaf(entry[]):
      discard pfree(pteToPa(entry[]), 1)
      entry[] = 0
    inc page

  flushTlb()
  0


proc freePageTablePages*(root: PageTable) =
  if root == nil:
    return

  var i = 0
  while i < 512:
    let entry = root[i]
    if pteIsValid(entry) and not pteIsLeaf(entry):
      freePageTablePages(cast[PageTable](pteToPa(entry)))
    inc i

  discard pfree(cast[PAddr](root), 1)


proc makeSatp*(rootPa: PAddr): U64 =
  SatpModeSv39 or (rootPa shr PageShift)


proc flushTlb*() =
  arch.flushTlb()
