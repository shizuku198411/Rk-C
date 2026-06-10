## Creates user processes and replaces process images during exec.
import ../../lib/fixed_string
import ../../lib/rkx
import ../../lib/syscall_caps
import ../../lib/syscall_types
import ../../lib/types
import ../../lib/user_ids
import ../dev/console
import ../mm/memory
import ../mm/paging
import ../security/rkx_trust
import ../task/process
import ../task/rkx_loader
import ../task/trusted_caps
import ../../platform/mmio_map
import ../../platform/service_policy

const
  ShellBase* = VAddr(0x01000000)
  ShellStackTop* = VAddr(0x01100000)
  AppBase* = VAddr(0x01200000)
  AppStackTop* = VAddr(0x01300000)
  UserArgMax = U64(256)

var
  textStartSym {.importc: "__text_start".}: char
  textEndSym {.importc: "__text_end".}: char
  rodataStartSym {.importc: "__rodata_start".}: char
  rodataEndSym {.importc: "__rodata_end".}: char
  dataStartSym {.importc: "__data_start".}: char
  freeRamEndSym {.importc: "__free_ram_end".}: char


## Copies arg.
proc copyArg(dst: PAddr, src: cstring, maxLen: U64) =
  let d = cast[ptr UncheckedArray[char]](dst)
  var i = U64(0)
  if src != nil:
    while i + 1 < maxLen and src[i] != '\0':
      d[i] = src[i]
      inc i
  d[i] = '\0'


## Implements the exec base for path kernel helper.
proc execBaseForPath(path: cstring): VAddr =
  if cstringEq(path, "/bin/shell"):
    return ShellBase

  AppBase


## Implements the exec stack top for path kernel helper.
proc execStackTopForPath(path: cstring): VAddr =
  if cstringEq(path, "/bin/shell"):
    return ShellStackTop

  AppStackTop


## Implements the stack pages from header kernel helper.
proc stackPagesFromHeader(hdr: ptr RkxHeader): U64 =
  if hdr == nil or hdr.stackPages == U32(0):
    return U64(RkxDefaultStackPages)

  U64(hdr.stackPages)


## Implements the granted caps for image kernel helper.
proc grantedCapsForImage(path: cstring, hdr: ptr RkxHeader): U32 =
  if hdr == nil:
    return SysCapNone

  if not rkxPathIntegrityVerified(path):
    return SysCapNone

  hdr.capabilityMask and trustedCapsForPath(path)


## Implements the allowed for uid kernel helper.
proc allowedForUid(hdr: ptr RkxHeader, uid: U32): bool =
  if hdr == nil or hdr.allowedUidCount == U32(0):
    return true

  var i = U32(0)
  while i < hdr.allowedUidCount and i < U32(RkxAllowedUidMax):
    if hdr.allowedUids[i] == uid:
      return true
    inc i

  false


## Implements the replace user stack kernel helper.
proc replaceUserStack(root: PageTable, stackTop: VAddr, stackPages: U64, arg: cstring,
                      userSp, argVa: var VAddr): int =
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


## Implements the install exec image kernel helper.
proc installExecImage(p: ptr Process, root: PageTable, path: cstring, base, stackTop: VAddr,
                      arg: cstring, allowedUid: U32, checkAllowedUid: bool): int =
  if root == nil:
    panic("missing process page table")

  var
    imagePages = U64(0)
    entryVa = VAddr(0)
    rkxHeader = RkxHeader()
  
  if loadRkxImage(root, path, base, imagePages, entryVa, addr rkxHeader) != 0:
    return -1

  if checkAllowedUid and not allowedForUid(addr rkxHeader, allowedUid):
    discard unmapRangeFree(root, base, imagePages)
    return int(SysExecPermission)

  let stackPages = stackPagesFromHeader(addr rkxHeader)
  var userSp = VAddr(0)
  var argVa = VAddr(0)
  if replaceUserStack(root, stackTop, stackPages, arg, userSp, argVa) != 0:
    return -1

  let requestedCaps = rkxHeader.capabilityMask
  let grantedCaps = grantedCapsForImage(path, addr rkxHeader)

  flushTlb()
  configureUserProcess(
    p,
    root,
    path,
    base,
    entryVa,
    stackTop,
    userSp,
    imagePages,
    stackPages,
    argVa,
    0,
    requestedCaps,
    grantedCaps,
  )
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


## Maps kernel ranges.
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

  if mapPlatformDeviceRanges(root) != 0:
    panic("failed to map platform device mmio")


## Creates kernel mapped page table.
proc createKernelMappedPageTable*(): PageTable =
  let root = allocPageTable()
  if root == nil:
    return nil

  mapKernelRanges(root)
  root


## Loads user process.
proc loadUserProcess(path: cstring, base, stackTop: VAddr, arg: cstring): int32 =
  let p = allocUserProcessFromParent(nil)
  if p == nil:
    return -1

  let root = createKernelMappedPageTable()
  if root == nil:
    discardProcess(p)
    return -1

  p.rootPageTable = root
  if installExecImage(p, root, path, base, stackTop, arg, RootUid, false) != 0:
    discardProcess(p)
    return -1

  p.pid


## Creates shell user process.
proc createShellUserProcess*(): int32 =
  loadUserProcess("/bin/shell", ShellBase, ShellStackTop, nil)


## Creates login user process.
proc createLoginUserProcess*(): int32 =
  loadUserProcess("/bin/login", AppBase, AppStackTop, nil)


## Creates service manager user process.
proc createServiceManagerUserProcess*(): int32 =
  loadUserProcess("/bin/svcmgtd", AppBase, AppStackTop, service_policy.serviceManagerArgs())


## Creates fs server user process.
proc createFsServerUserProcess*(): int32 =
  loadUserProcess("/bin/fsd", AppBase, AppStackTop, nil)


## Creates block server user process.
proc createBlockServerUserProcess*(): int32 =
  loadUserProcess("/bin/blockd", AppBase, AppStackTop, nil)


## Implements the exec user app with identity kernel helper.
proc execUserAppWithIdentity(path: cstring, arg: cstring, detached: bool,
                             uid, gid: U32): int32 =
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

  let installRc = installExecImage(child, root, path, childBase, childStackTop, arg, uid, true)
  if installRc != 0:
    discardProcess(child)
    return int32(installRc)

  inheritProcessMetadata(child, parent)
  child.identity.uid = uid
  child.identity.gid = gid
  if parent == nil or parent.identity.uid != uid or parent.identity.gid != gid:
    initDefaultEnvForIdentity(child, uid, gid)
  else:
    syncPwdEnv(child)
  child.pid


## Implements the exec user app kernel helper.
proc execUserApp*(path: cstring, arg: cstring, detached: bool = false): int32 =
  let parent = currentProc
  let uid =
    if parent == nil:
      RootUid
    else:
      parent.identity.uid
  let gid =
    if parent == nil:
      RootGid
    else:
      parent.identity.gid

  execUserAppWithIdentity(path, arg, detached, uid, gid)


## Implements the exec user app as kernel helper.
proc execUserAppAs*(path: cstring, arg: cstring, uid, gid: U32): int32 =
  execUserAppWithIdentity(path, arg, false, uid, gid)
