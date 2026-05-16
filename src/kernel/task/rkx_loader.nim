import ../../lib/mem
import ../../lib/rkx
import ../../lib/types
import ../dev/console
import ../fs/fs
import ../mm/memory
import ../mm/paging


const
  RkxImageMaxPages* = U64(64)
  RkxImageMaxSIze* = RkxImageMaxPages * PageSize
  UserImageVaSizeLimit = U64(0x00100000)


proc checkedAdd(a, b: U64, outValue: var U64): bool =
  outValue = a + b
  outValue >= a


proc checkedRange(start, size: U64, outEnd: var U64): bool =
  if size == U64(0):
    outEnd = start
    return true

  checkedAdd(start, size, outEnd)


proc rangeWithin(start, size, base, limit: U64): bool =
  var endExclusive = U64(0)

  if not checkedRange(start, size, endExclusive):
    return false

  if start < base:
    return false

  endExclusive <= limit


proc minU64(a, b: U64): U64 =
  if a < b:
    a
  else:
    b


proc segmentPages(memSize: U64): U64 =
  if memSize == U64(0):
    return U64(0)

  alignUp(memSize, PageSize) div PageSize


proc validateFileRange(fileOff, fileSize, imageSize: U64): bool =
  var fileEnd = U64(0)

  if not checkedRange(fileOff, fileSize, fileEnd):
    return false

  fileEnd <= imageSize


proc validateSegment(
  va: VAddr,
  fileOff: U64,
  fileSize: U64,
  memSize: U64,
  imageSize: U64,
  expectedBase: VAddr
): bool =
  if memSize == 0.U64:
    return fileSize == 0.U64

  if not isAligned(va, PageSize):
    return false

  if fileSize > memSize:
    return false

  if not validateFileRange(fileOff, fileSize, imageSize):
    return false

  let imageLimit = expectedBase + UserImageVaSizeLimit
  if not rangeWithin(va, memSize, expectedBase, imageLimit):
    return false

  true


proc rangesOverlap(aStart, aSize, bStart, bSize: U64): bool =
  if aSize == 0.U64 or bSize == 0.U64:
    return false

  var aEnd = U64(0)
  var bEnd = U64(0)
  if not checkedRange(aStart, aSize, aEnd):
    return true
  if not checkedRange(bStart, bSize, bEnd):
    return true

  aStart < bEnd and bStart < aEnd


proc validateSegmentLayout(hdr: ptr RkxHeader): bool =
  if rangesOverlap(hdr.textVa, hdr.textMemSize, hdr.rodataVa, hdr.rodataMemSize):
    return false
  if rangesOverlap(hdr.textVa, hdr.textMemSize, hdr.dataVa, hdr.dataMemSize):
    return false
  if rangesOverlap(hdr.textVa, hdr.textMemSize, hdr.bssVa, hdr.bssMemSize):
    return false
  if rangesOverlap(hdr.rodataVa, hdr.rodataMemSize, hdr.dataVa, hdr.dataMemSize):
    return false
  if rangesOverlap(hdr.rodataVa, hdr.rodataMemSize, hdr.bssVa, hdr.bssMemSize):
    return false
  if rangesOverlap(hdr.dataVa, hdr.dataMemSize, hdr.bssVa, hdr.bssMemSize):
    return false

  true


proc validateRkxHeader(hdr: ptr RkxHeader, imageSize: U64, expectedBase: VAddr): bool =
  if hdr == nil:
    return false

  if hdr.magic != RkxMagic:
    return false

  if hdr.version != RkxVersion:
    return false

  if hdr.headerSize < U32(sizeof(RkxHeader)):
    return false

  if U64(hdr.headerSize) > imageSize:
    return false

  if not validateSegment(
    hdr.textVa,
    hdr.textOff,
    hdr.textFileSize,
    hdr.textMemSize,
    imageSize,
    expectedBase
  ):
    return false

  if not validateSegment(
    hdr.rodataVa,
    hdr.rodataOff,
    hdr.rodataFileSize,
    hdr.rodataMemSize,
    imageSize,
    expectedBase
  ):
    return false

  if not validateSegment(
    hdr.dataVa,
    hdr.dataOff,
    hdr.dataFileSize,
    hdr.dataMemSize,
    imageSize,
    expectedBase
  ):
    return false

  if hdr.bssMemSize > 0.U64:
    if not isAligned(hdr.bssVa, PageSize):
      return false

    let imageLimit = expectedBase + UserImageVaSizeLimit
    if not rangeWithin(hdr.bssVa, hdr.bssMemSize, expectedBase, imageLimit):
      return false

  if not validateSegmentLayout(hdr):
    return false

  # entry は text 内にある必要がある。
  if hdr.textMemSize == 0.U64:
    return false

  var textEnd = U64(0)
  if not checkedRange(hdr.textVa, hdr.textMemSize, textEnd):
    return false

  if hdr.entryVa < hdr.textVa or hdr.entryVa >= textEnd:
    return false

  true


proc mapOnePage(root: PageTable, va: VAddr, pa: PAddr, flags: U64): int =
  if mapPageReplaceFree(root, va, pa, flags) != 0:
    return -1

  0


proc mapRkxSegment(
  root: PageTable,
  image: ptr UncheckedArray[U8],
  imageSize: U64,
  va: VAddr,
  fileOff: U64,
  fileSize: U64,
  memSize: U64,
  flags: U64
): int =
  if memSize == 0.U64:
    return 0

  if image == nil:
    return -1

  if not validateFileRange(fileOff, fileSize, imageSize):
    return -1

  let pages = segmentPages(memSize)
  var page = U64(0)

  while page < pages:
    let pagePa = palloc(1.U64)
    if pagePa == NilPAddr:
      discard unmapRangeFree(root, va, page)
      return -1

    # palloc() 側で zeroMem 済みだけど、segment tail / bss 相当の明示のためにそのまま使う。
    let segOff = page * PageSize

    if segOff < fileSize:
      let remaining = fileSize - segOff
      let copySize = minU64(PageSize, remaining)

      discard copyMem(
        cast[pointer](pagePa),
        cast[pointer](addr image[fileOff + segOff]),
        copySize
      )

    if mapOnePage(root, va + segOff, pagePa, flags) != 0:
      discard pfree(pagePa, 1.U64)
      discard unmapRangeFree(root, va, page)
      return -1

    inc page

  0


proc mapZeroSegment(
  root: PageTable,
  va: VAddr,
  memSize: U64,
  flags: U64
): int =
  if memSize == 0.U64:
    return 0

  let pages = segmentPages(memSize)
  var page = U64(0)

  while page < pages:
    let pagePa = palloc(1.U64)
    if pagePa == NilPAddr:
      discard unmapRangeFree(root, va, page)
      return -1

    # palloc() で zeroMem 済み。

    if mapOnePage(root, va + page * PageSize, pagePa, flags) != 0:
      discard pfree(pagePa, 1.U64)
      discard unmapRangeFree(root, va, page)
      return -1

    inc page

  0


proc cleanupRkxMappings(root: PageTable, hdr: ptr RkxHeader) =
  if root == nil or hdr == nil:
    return

  discard unmapRangeFree(root, hdr.textVa, segmentPages(hdr.textMemSize))
  discard unmapRangeFree(root, hdr.rodataVa, segmentPages(hdr.rodataMemSize))
  discard unmapRangeFree(root, hdr.dataVa, segmentPages(hdr.dataMemSize))
  discard unmapRangeFree(root, hdr.bssVa, segmentPages(hdr.bssMemSize))


proc calcImagePages(hdr: ptr RkxHeader, expectedBase: VAddr, imagePages: var U64): bool =
  var maxEnd = expectedBase

  template updateEnd(va: VAddr, memSize: U64): bool =
    block:
      var e = U64(0)
      if not checkedRange(va, memSize, e):
        false
      else:
        if e > maxEnd:
          maxEnd = e
        true

  if not updateEnd(hdr.textVa, hdr.textMemSize):
    return false

  if not updateEnd(hdr.rodataVa, hdr.rodataMemSize):
    return false

  if not updateEnd(hdr.dataVa, hdr.dataMemSize):
    return false

  if not updateEnd(hdr.bssVa, hdr.bssMemSize):
    return false

  if maxEnd < expectedBase:
    return false

  imagePages = alignUp(maxEnd - expectedBase, PageSize) div PageSize
  true


proc loadRkxImage*(
  root: PageTable,
  path: cstring,
  expectedBase: VAddr,
  imagePages: var U64,
  entryVa: var VAddr
): int =
  if root == nil or path == nil:
    return -1

  imagePages = 0.U64
  entryVa = 0.U64

  let imagePa = palloc(RkxImageMaxPages)
  if imagePa == NilPAddr:
    panic("failed to allocate rkx load buffer")

  let loaded = fsReadFile(path, cast[pointer](imagePa), RkxImageMaxSize)
  if loaded <= 0:
    discard pfree(imagePa, RkxImageMaxPages)
    return -1

  let imageSize = U64(loaded)
  if imageSize < U64(sizeof(RkxHeader)):
    discard pfree(imagePa, RkxImageMaxPages)
    return -1

  let image = cast[ptr UncheckedArray[U8]](imagePa)
  let hdr = cast[ptr RkxHeader](imagePa)

  if not validateRkxHeader(hdr, imageSize, expectedBase):
    discard pfree(imagePa, RkxImageMaxPages)
    return -1

  if mapRkxSegment(
    root,
    image,
    imageSize,
    hdr.textVa,
    hdr.textOff,
    hdr.textFileSize,
    hdr.textMemSize,
    PteU or PteR or PteX
  ) != 0:
    discard pfree(imagePa, RkxImageMaxPages)
    return -1

  if mapRkxSegment(
    root,
    image,
    imageSize,
    hdr.rodataVa,
    hdr.rodataOff,
    hdr.rodataFileSize,
    hdr.rodataMemSize,
    PteU or PteR
  ) != 0:
    cleanupRkxMappings(root, hdr)
    discard pfree(imagePa, RkxImageMaxPages)
    return -1

  if mapRkxSegment(
    root,
    image,
    imageSize,
    hdr.dataVa,
    hdr.dataOff,
    hdr.dataFileSize,
    hdr.dataMemSize,
    PteU or PteR or PteW
  ) != 0:
    cleanupRkxMappings(root, hdr)
    discard pfree(imagePa, RkxImageMaxPages)
    return -1

  if mapZeroSegment(
    root,
    hdr.bssVa,
    hdr.bssMemSize,
    PteU or PteR or PteW
  ) != 0:
    cleanupRkxMappings(root, hdr)
    discard pfree(imagePa, RkxImageMaxPages)
    return -1

  if not calcImagePages(hdr, expectedBase, imagePages):
    cleanupRkxMappings(root, hdr)
    discard pfree(imagePa, RkxImageMaxPages)
    return -1

  entryVa = hdr.entryVa

  discard pfree(imagePa, RkxImageMaxPages)
  flushTlb()
  0
