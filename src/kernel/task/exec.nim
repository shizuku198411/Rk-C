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
  UserArgMax = U64(128)

proc copyArg(dst: PAddr, src: cstring, maxLen: U64) =
  let d = cast[ptr UncheckedArray[char]](dst)
  var i = U64(0)
  if src != nil:
    while i + 1 < maxLen and src[i] != '\0':
      d[i] = src[i]
      inc i
  d[i] = '\0'

proc loadUserProcess(path: cstring, base, stackTop: VAddr, arg: cstring): int32 =
  let root = getKernelRootPageTable()
  if root == nil:
    panic("missing kernel page table")

  let imagePa = palloc(UserImageMaxPages)
  if imagePa == NilPAddr:
    panic("failed to allocate user image")

  let loaded = fsReadFile(path, cast[pointer](imagePa), UserImageMaxSize)
  if loaded <= 0:
    return -1

  let imageSize = U64(loaded)
  let imagePages = alignUp(imageSize, PageSize) div PageSize

  if mapRangeReplace(root, base, imagePa, imagePages * PageSize, PteU or PteR or PteW or PteX) != 0:
    panic("failed to map user image")

  let stackPa = palloc(1)
  if stackPa == NilPAddr:
    panic("failed to allocate user stack")

  if mapPageReplace(root, stackTop - PageSize, stackPa, PteU or PteR or PteW) != 0:
    panic("failed to map user stack")

  let argPa = stackPa + PageSize - UserArgMax
  let argVa = stackTop - UserArgMax
  let userSp = argVa
  copyArg(argPa, arg, UserArgMax)

  flushTlb()
  createUserProcess(path, base, userSp, argVa, 0)

proc createShellUserProcess*(): int32 =
  loadUserProcess("/bin/shell", ShellBase, ShellStackTop, nil)

proc execUserApp*(path: cstring, arg: cstring): int32 =
  loadUserProcess(path, AppBase, AppStackTop, arg)
