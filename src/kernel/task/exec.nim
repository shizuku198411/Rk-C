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


proc pathEquals(path: cstring, expected: cstring): bool =
  var i = 0
  while true:
    let a = path[i]
    let b = expected[i]
    if a != b:
      return false
    if a == '\0':
      return true
    inc i


proc execBaseForPath(path: cstring): VAddr =
  if path != nil and pathEquals(path, "/bin/shell"):
    return ShellBase

  AppBase


proc execStackTopForPath(path: cstring): VAddr =
  if path != nil and pathEquals(path, "/bin/shell"):
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


proc cloneParentUserMemory(childRoot: PageTable, parent: ptr Process, childBase, childStackTop: VAddr): int =
  if parent == nil or not parent.isUser:
    return 0

  let parentRoot =
    if parent.rootPageTable != nil:
      parent.rootPageTable
    else:
      getKernelRootPageTable()

  if parentRoot == nil:
    return -1

  if cloneMappedRange(parentRoot, childRoot, parent.userBase, childBase, parent.userImagePages,
                      PteU or PteR or PteW or PteX) != 0:
    return -1

  let parentStackBase = parent.userStackTop - parent.userStackPages * PageSize
  let childStackBase = childStackTop - parent.userStackPages * PageSize
  if cloneMappedRange(parentRoot, childRoot, parentStackBase, childStackBase, parent.userStackPages,
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

  if mapRangeReplaceFree(root, base, imagePa, imagePages * PageSize, PteU or PteR or PteW or PteX) != 0:
    panic("failed to map user image")

  0


proc replaceUserStack(root: PageTable, stackTop: VAddr, arg: cstring, userSp, argVa: var VAddr): int =
  let stackPa = palloc(UserStackPages)
  if stackPa == NilPAddr:
    panic("failed to allocate user stack")

  if mapPageReplaceFree(root, stackTop - PageSize, stackPa, PteU or PteR or PteW) != 0:
    panic("failed to map user stack")

  let argPa = stackPa + PageSize - UserArgMax
  argVa = stackTop - UserArgMax
  userSp = argVa
  copyArg(argPa, arg, UserArgMax)
  0


proc installExecImage(p: ptr Process, root: PageTable, path: cstring, base, stackTop: VAddr, arg: cstring): int =
  if root == nil:
    panic("missing process page table")

  var imagePages = U64(0)
  if replaceUserImage(root, path, base, imagePages) != 0:
    return -1

  var userSp = VAddr(0)
  var argVa = VAddr(0)
  if replaceUserStack(root, stackTop, arg, userSp, argVa) != 0:
    return -1

  flushTlb()
  configureUserProcess(p, root, path, base, base, stackTop, userSp, imagePages, UserStackPages, argVa, 0)
  0


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
  if parent != nil and parent.isUser:
    child.userBase = childBase
    child.userStackTop = childStackTop
    child.userImagePages = parent.userImagePages
    child.userStackPages = parent.userStackPages

  if cloneParentUserMemory(root, parent, childBase, childStackTop) != 0:
    discardProcess(child)
    return -1

  if installExecImage(child, root, path, childBase, childStackTop, arg) != 0:
    discardProcess(child)
    return -1

  child.pid
