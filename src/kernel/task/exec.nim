import ../../lib/mem
import ../../lib/types
import ../dev/console
import ../fs/fs
import ../init/bootstrap
import ../mm/memory
import ../mm/paging
import ../task/process

const
  ShellBase* = VAddr(0x01000000)
  ShellStackTop* = VAddr(0x01100000)
  AppBase* = VAddr(0x01200000)
  AppStackTop* = VAddr(0x01300000)
  UserImageMaxPages = U64(16)
  UserImageMaxSize = UserImageMaxPages * PageSize
  UserStackPages = U64(1)
  UserArgMax = U64(128)


proc copyArg(dst: PAddr, src: cstring, maxLen: U64) =
  let d = cast[ptr UncheckedArray[char]](dst)
  var i = U64(0)
  if src != nil:
    while i + 1 < maxLen and src[i] != '\0':
      d[i] = src[i]
      inc i
  d[i] = '\0'


proc copyPage(dstPa, srcPa: PAddr) =
  discard copyMem(cast[pointer](dstPa), cast[pointer](srcPa), PageSize)


proc cloneMappedRange(root: PageTable, srcBase, dstBase: VAddr, pages: U64, flags: U64): int =
  if pages == 0:
    return 0
  if srcBase == 0 or dstBase == 0:
    return 0

  var page = U64(0)
  while page < pages:
    let off = page * PageSize
    let srcPa = mappedPagePa(root, srcBase + off)
    if srcPa == NilPAddr:
      return -1

    let dstPa = palloc(1)
    if dstPa == NilPAddr:
      return -1

    copyPage(dstPa, srcPa)
    if mapPageReplace(root, dstBase + off, dstPa, flags) != 0:
      return -1

    inc page

  0


proc cloneParentUserMemory(root: PageTable, parent: ptr Process, childBase, childStackTop: VAddr): int =
  if parent == nil or not parent.isUser:
    return 0

  if parent.userBase != childBase:
    if cloneMappedRange(root, parent.userBase, childBase, parent.userImagePages,
                        PteU or PteR or PteW or PteX) != 0:
      return -1

  let parentStackBase = parent.userStackTop - parent.userStackPages * PageSize
  let childStackBase = childStackTop - parent.userStackPages * PageSize
  if parentStackBase != childStackBase:
    if cloneMappedRange(root, parentStackBase, childStackBase, parent.userStackPages,
                        PteU or PteR or PteW) != 0:
      return -1

  flushTlb()
  0


proc replaceUserImage(root: PageTable, path: cstring, base: VAddr, imagePages: var U64): int =
  let imagePa = palloc(UserImageMaxPages)
  if imagePa == NilPAddr:
    panic("failed to allocate user image")

  let loaded = fsReadFile(path, cast[pointer](imagePa), UserImageMaxSize)
  if loaded <= 0:
    discard pfree(imagePa, UserImageMaxPages)
    return -1

  imagePages = UserImageMaxPages

  if mapRangeReplace(root, base, imagePa, imagePages * PageSize, PteU or PteR or PteW or PteX) != 0:
    panic("failed to map user image")

  0


proc replaceUserStack(root: PageTable, stackTop: VAddr, arg: cstring, userSp, argVa: var VAddr): int =
  let stackPa = palloc(UserStackPages)
  if stackPa == NilPAddr:
    panic("failed to allocate user stack")

  if mapPageReplace(root, stackTop - PageSize, stackPa, PteU or PteR or PteW) != 0:
    panic("failed to map user stack")

  let argPa = stackPa + PageSize - UserArgMax
  argVa = stackTop - UserArgMax
  userSp = argVa
  copyArg(argPa, arg, UserArgMax)
  0


proc installExecImage(p: ptr Process, path: cstring, base, stackTop: VAddr, arg: cstring): int =
  let root = getKernelRootPageTable()
  if root == nil:
    panic("missing kernel page table")

  var imagePages = U64(0)
  if replaceUserImage(root, path, base, imagePages) != 0:
    return -1

  var userSp = VAddr(0)
  var argVa = VAddr(0)
  if replaceUserStack(root, stackTop, arg, userSp, argVa) != 0:
    return -1

  flushTlb()
  configureUserProcess(p, path, base, base, stackTop, userSp, imagePages, UserStackPages, argVa, 0)
  0


proc loadUserProcess(path: cstring, base, stackTop: VAddr, arg: cstring): int32 =
  let p = allocUserProcessFromParent(nil)
  if p == nil:
    return -1

  if installExecImage(p, path, base, stackTop, arg) != 0:
    discardProcess(p)
    return -1

  p.pid


proc createShellUserProcess*(): int32 =
  loadUserProcess("/bin/shell", ShellBase, ShellStackTop, nil)


proc execUserApp*(path: cstring, arg: cstring): int32 =
  let parent = currentProc
  let child = allocUserProcessFromParent(parent)
  if child == nil:
    return -1

  let root = getKernelRootPageTable()
  if root == nil:
    panic("missing kernel page table")

  if cloneParentUserMemory(root, parent, AppBase, AppStackTop) != 0:
    discardProcess(child)
    return -1

  if installExecImage(child, path, AppBase, AppStackTop, arg) != 0:
    discardProcess(child)
    return -1

  child.pid
