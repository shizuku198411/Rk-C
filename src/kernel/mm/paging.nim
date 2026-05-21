## Manages Sv39 page tables, mappings, and TLB updates.
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
  
  Sv39SignBit = U64(1) shl 38
  Sv39LowTop = U64(1) shl 38
  Sv39HighBase = not ((U64(1) shl 39) - U64(1))


## Returns the Sv39 level-0 VPN index for a virtual address.
func sv39Vpn0(va: VAddr): U64 {.inline.} = (va shr 12) and VpnMask
## Returns the Sv39 level-1 VPN index for a virtual address.
func sv39Vpn1(va: VAddr): U64 {.inline.} = (va shr 21) and VpnMask
## Returns the Sv39 level-2 VPN index for a virtual address.
func sv39Vpn2(va: VAddr): U64 {.inline.} = (va shr 30) and VpnMask
## Returns whether a page-table entry is valid.
func pteIsValid(pte: Pte): bool {.inline.} = (pte and PteV) != 0
## Returns whether a page-table entry maps a leaf page.
func pteIsLeaf(pte: Pte): bool {.inline.} = (pte and (PteR or PteW or PteX)) != 0
## Converts a page-table entry into a physical address.
func pteToPa(pte: Pte): PAddr {.inline.} = (pte shr 10) shl PageShift
## Converts a physical address into page-table entry address bits.
func paToPte(pa: PAddr): Pte {.inline.} = (pa shr PageShift) shl 10


## Returns whether sv39 canonical is true.
proc isSv39Canonical(va: VAddr): bool =
  if (va and Sv39SignBit) == U64(0):
    return va < Sv39LowTop

  (va and Sv39HighBase) == Sv39HighBase


## Allocates page table.
proc allocPageTable*(): PageTable =
  let pa = palloc(1)
  if pa == NilPAddr:
    return nil
  cast[PageTable](pa)


## Implements the walk page table kernel helper.
proc walkPageTable*(root: PageTable, va: VAddr, create: bool): ptr Pte =
  let indexes = [sv39Vpn0(va), sv39Vpn1(va), sv39Vpn2(va)]
  var table = root
  var level = 2

  if not isSv39Canonical(va):
    return nil

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


## Maps page.
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


## Maps page replace.
proc mapPageReplace*(root: PageTable, va: VAddr, pa: PAddr, flags: U64): int =
  if not isAligned(va, PageSize) or not isAligned(pa, PageSize):
    return -1

  let entry = walkPageTable(root, va, true)
  if entry == nil:
    return -1

  entry[] = paToPte(pa) or flags or PteV or PteA or PteD
  0


## Maps page replace free.
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


## Maps range.
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


## Maps range replace.
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


## Maps range replace free.
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


## Maps mapped page pa.
proc mappedPagePa*(root: PageTable, va: VAddr): PAddr =
  let entry = walkPageTable(root, alignDown(va, PageSize), false)
  if entry == nil or not pteIsValid(entry[]) or not pteIsLeaf(entry[]):
    return NilPAddr

  pteToPa(entry[])


## Maps mapped page flags.
proc mappedPageFlags*(root: PageTable, va: VAddr): U64 =
  let entry = walkPageTable(root, alignDown(va, PageSize), false)
  if entry == nil or not pteIsValid(entry[]) or not pteIsLeaf(entry[]):
    return 0

  entry[] and 0x3ff'u64


## Unmaps range free.
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


## Frees page table pages.
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


## Builds satp.
proc makeSatp*(rootPa: PAddr): U64 =
  SatpModeSv39 or (rootPa shr PageShift)


## Implements the flush tlb kernel helper.
proc flushTlb*() =
  arch.flushTlb()
