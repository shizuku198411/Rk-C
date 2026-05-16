import ../../lib/fixed_string
import ../../lib/mem
import ../../lib/types
import ../dev/console
import ../mm/memory
import ../mm/paging
import ../task/process
import ../task/rkx_loader

const
  ShellBase* = VAddr(0x01000000)
  ShellStackTop* = VAddr(0x01100000)
  AppBase* = VAddr(0x01200000)
  AppStackTop* = VAddr(0x01300000)
  UserStackPages = U64(4)
  UserArgMax = U64(128)

  QemuUart0Base = PAddr(0x10000000)
  QemuMmioSize = U64(0x00010000)
  QemuPlicBase = PAddr(0x0c000000)
  QemuPlicSize = U64(0x00400000)
  QemuRtcBase = PAddr(0x00101000)
  QemuRtcSize = U64(0x00001000)


var
  textStartSym {.importc: "__text_start".}: char
  textEndSym {.importc: "__text_end".}: char
  rodataStartSym {.importc: "__rodata_start".}: char
  rodataEndSym {.importc: "__rodata_end".}: char
  dataStartSym {.importc: "__data_start".}: char
  freeRamEndSym {.importc: "__free_ram_end".}: char
  kernelRootPageTable: PageTable


proc copyArg(dst: PAddr, src: cstring, maxLen: U64) =
  let d = cast[ptr UncheckedArray[char]](dst)
  var i = U64(0)
  if src != nil:
    while i + 1 < maxLen and src[i] != '\0':
      d[i] = src[i]
      inc i
  d[i] = '\0'


proc execBaseForPath(path: cstring): VAddr =
  if cstringEq(path, "/bin/shell"):
    return ShellBase

  AppBase


proc execStackTopForPath(path: cstring): VAddr =
  if cstringEq(path, "/bin/shell"):
    return ShellStackTop

  AppStackTop


proc copyPage(dstPa, srcPa: PAddr) =
  discard copyMem(cast[pointer](dstPa), cast[pointer](srcPa), PageSize)


proc cloneMappedRange(srcRoot, dstRoot: PageTable, srcBase, dstBase: VAddr, pages: U64, flags: U64): int =
  if pages == 0:
    return 0
  if srcBase == 0 or dstBase == 0:
    return 0

  var page = U64(0)
  while page < pages:
    let off = page * PageSize
    let srcPa = mappedPagePa(srcRoot, srcBase + off)
    if srcPa == NilPAddr:
      return -1

    let dstPa = palloc(1)
    if dstPa == NilPAddr:
      return -1

    copyPage(dstPa, srcPa)
    if mapPageReplace(dstRoot, dstBase + off, dstPa, flags) != 0:
      discard pfree(dstPa, 1)
      return -1

    inc page

  0


proc getKernelRootPageTable(): PageTable =
  kernelRootPageTable


proc cloneParentUserMemory(childRoot: PageTable, parent: ptr Process, childBase, childStackTop: VAddr): int =
  if parent == nil or not parent.user.active:
    return 0

  let parentRoot =
    if parent.rootPageTable != nil:
      parent.rootPageTable
    else:
      getKernelRootPageTable()

  if parentRoot == nil:
    return -1

  if cloneMappedRange(parentRoot, childRoot, parent.user.base, childBase, parent.user.imagePages,
                      PteU or PteR or PteW or PteX) != 0:
    return -1

  let parentStackBase = parent.user.stackTop - parent.user.stackPages * PageSize
  let childStackBase = childStackTop - parent.user.stackPages * PageSize
  if cloneMappedRange(parentRoot, childRoot, parentStackBase, childStackBase, parent.user.stackPages,
                      PteU or PteR or PteW) != 0:
    return -1

  flushTlb()
  0


proc replaceUserStack(root: PageTable, stackTop: VAddr, arg: cstring, userSp, argVa: var VAddr): int =
  let stackPa = palloc(UserStackPages)
  if stackPa == NilPAddr:
    panic("failed to allocate user stack")

  if mapRangeReplaceFree(root, stackTop - UserStackPages * PageSize, stackPa,
                         UserStackPages * PageSize, PteU or PteR or PteW) != 0:
    panic("failed to map user stack")

  let argPa = stackPa + UserStackPages * PageSize - UserArgMax
  argVa = stackTop - UserArgMax
  userSp = argVa
  copyArg(argPa, arg, UserArgMax)
  0


proc installExecImage(p: ptr Process, root: PageTable, path: cstring, base, stackTop: VAddr, arg: cstring): int =
  if root == nil:
    panic("missing process page table")

  var
    imagePages = U64(0)
    entryVa = VAddr(0)
  
  if loadRkxImage(root, path, base, imagePages, entryVa) != 0:
    return -1

  var userSp = VAddr(0)
  var argVa = VAddr(0)
  if replaceUserStack(root, stackTop, arg, userSp, argVa) != 0:
    return -1

  flushTlb()
  configureUserProcess(p, root, path, base, entryVa, stackTop, userSp, imagePages, UserStackPages, argVa, 0)
  0


proc mapKernelRanges(root: PageTable) =
  let textStart = alignDown(cast[VAddr](addr textStartSym), PageSize)
  let textSize = alignUp(cast[U64](addr textEndSym) - textStart, PageSize)
  let rodataStart = alignDown(cast[VAddr](addr rodataStartSym), PageSize)
  let rodataSize = alignUp(cast[U64](addr rodataEndSym) - rodataStart, PageSize)
  let dataStart = alignDown(cast[VAddr](addr dataStartSym), PageSize)
  let dataSize = alignUp(cast[U64](addr freeRamEndSym) - dataStart, PageSize)

  if mapRange(root, textStart, textStart, textSize, PteR or PteX) != 0:
    panic("failed to map kernel text range")

  if mapRange(root, rodataStart, rodataStart, rodataSize, PteR) != 0:
    panic("failed to map kernel rodata range")

  if mapRange(root, dataStart, dataStart, dataSize, PteR or PteW) != 0:
    panic("failed to map kernel data range")

  if mapRange(root, QemuUart0Base, QemuUart0Base, QemuMmioSize, PteR or PteW) != 0:
    panic("failed to map qemu mmio")

  if mapRange(root, QemuPlicBase, QemuPlicBase, QemuPlicSize, PteR or PteW) != 0:
    panic("failed to map plic mmio")

  if mapRange(root, QemuRtcBase, QemuRtcBase, QemuRtcSize, PteR or PteW) != 0:
    panic("failed to map rtc mmio")


proc createKernelMappedPageTable*(): PageTable =
  let root = allocPageTable()
  if root == nil:
    return nil

  mapKernelRanges(root)
  root


proc loadUserProcess(path: cstring, base, stackTop: VAddr, arg: cstring): int32 =
  let p = allocUserProcessFromParent(nil)
  if p == nil:
    return -1

  let root = createKernelMappedPageTable()
  if root == nil:
    discardProcess(p)
    return -1

  p.rootPageTable = root
  if installExecImage(p, root, path, base, stackTop, arg) != 0:
    discardProcess(p)
    return -1

  p.pid


proc createShellUserProcess*(): int32 =
  loadUserProcess("/bin/shell", ShellBase, ShellStackTop, nil)


proc createServiceManagerUserProcess*(): int32 =
  loadUserProcess("/bin/svcmgtd", AppBase, AppStackTop, nil)


proc createFsServerUserProcess*(): int32 =
  loadUserProcess("/bin/fsd", AppBase, AppStackTop, nil)


proc createBlockServerUserProcess*(): int32 =
  loadUserProcess("/bin/blockd", AppBase, AppStackTop, nil)


proc execUserApp*(path: cstring, arg: cstring, detached: bool = false): int32 =
  let parent = currentProc
  let child = allocUserProcessFromParent(parent)
  if child == nil:
    return -1

  child.detached = detached

  let root = createKernelMappedPageTable()
  if root == nil:
    discardProcess(child)
    return -1

  let childBase = execBaseForPath(path)
  let childStackTop = execStackTopForPath(path)
  child.rootPageTable = root
  if parent != nil and parent.user.active:
    child.user.base = childBase
    child.user.stackTop = childStackTop
    child.user.imagePages = parent.user.imagePages
    child.user.stackPages = parent.user.stackPages

  if cloneParentUserMemory(root, parent, childBase, childStackTop) != 0:
    discardProcess(child)
    return -1

  if installExecImage(child, root, path, childBase, childStackTop, arg) != 0:
    discardProcess(child)
    return -1

  child.pid
