import ../../lib/fixed_string
import ../../lib/rkx
import ../../lib/syscall_types
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


proc stackPagesFromHeader(hdr: ptr RkxHeader): U64 =
  if hdr == nil or hdr.stackPages == U32(0):
    return U64(RkxDefaultStackPages)

  U64(hdr.stackPages)


proc replaceUserStack(root: PageTable, stackTop: VAddr, stackPages: U64, arg: cstring, userSp, argVa: var VAddr): int =
  if stackPages < U64(RkxMinStackPages) or stackPages > U64(RkxMaxStackPages):
    return -1

  let stackPa = palloc(stackPages)
  if stackPa == NilPAddr:
    panic("failed to allocate user stack")

  if mapRangeReplaceFree(root, stackTop - stackPages * PageSize, stackPa,
                         stackPages * PageSize, PteU or PteR or PteW) != 0:
    panic("failed to map user stack")

  let argPa = stackPa + stackPages * PageSize - UserArgMax
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
    rkxHeader = RkxHeader()
  
  if loadRkxImage(root, path, base, imagePages, entryVa, addr rkxHeader) != 0:
    return -1

  let stackPages = stackPagesFromHeader(addr rkxHeader)
  var userSp = VAddr(0)
  var argVa = VAddr(0)
  if replaceUserStack(root, stackTop, stackPages, arg, userSp, argVa) != 0:
    return -1

  flushTlb()
  configureUserProcess(p, root, path, base, entryVa, stackTop, userSp, imagePages, stackPages, argVa, 0)
  setUserRkxMap(
    p,
    rkxHeader.textVa,
    rkxHeader.textMemSize,
    rkxHeader.rodataVa,
    rkxHeader.rodataMemSize,
    rkxHeader.dataVa,
    rkxHeader.dataMemSize,
    rkxHeader.bssVa,
    rkxHeader.bssMemSize,
  )
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
  if not hasFreeProcessSlot():
    return SysExecNoProcess

  let child = allocUserProcessFromParent(parent, false)
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

  if installExecImage(child, root, path, childBase, childStackTop, arg) != 0:
    discardProcess(child)
    return -1

  inheritProcessMetadata(child, parent)
  child.pid
