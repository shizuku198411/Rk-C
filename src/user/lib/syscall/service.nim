## Provides wrappers for service manager and service-backed syscalls.
import ./base
import ../../../lib/syscall_ids


## Invokes the fs service register syscall wrapper.
proc sysFsServiceRegister*(): I32 =
  I32(rawSyscall3(SysFsServiceRegister, 0, 0, 0))


## Invokes the fs service receive syscall wrapper.
proc sysFsServiceReceive*(req: ptr SysFsRequest): I32 =
  I32(rawSyscall3(SysFsServiceReceive, cast[U64](req), 0, 0))


## Invokes the fs service reply syscall wrapper.
proc sysFsServiceReply*(resp: ptr SysFsResponse): I32 =
  I32(rawSyscall3(SysFsServiceReply, cast[U64](resp), 0, 0))


## Invokes the block service register syscall wrapper.
proc sysBlockServiceRegister*(): I32 =
  I32(rawSyscall3(SysBlockServiceRegister, 0, 0, 0))


## Invokes the block service receive syscall wrapper.
proc sysBlockServiceReceive*(req: ptr SysBlockRequest): I32 =
  I32(rawSyscall3(SysBlockServiceReceive, cast[U64](req), 0, 0))


## Invokes the block service reply syscall wrapper.
proc sysBlockServiceReply*(resp: ptr SysBlockResponse): I32 =
  I32(rawSyscall3(SysBlockServiceReply, cast[U64](resp), 0, 0))


## Invokes the raw block read syscall wrapper.
proc sysRawBlockRead*(blockIndex: U64, outBlock: pointer): I32 =
  I32(rawSyscall3(SysRawBlockRead, blockIndex, cast[U64](outBlock), 0))


## Invokes the raw block write syscall wrapper.
proc sysRawBlockWrite*(blockIndex: U64, inBlock: pointer): I32 =
  I32(rawSyscall3(SysRawBlockWrite, blockIndex, cast[U64](inBlock), 0))


## Invokes the service manager register syscall wrapper.
proc sysServiceManagerRegister*(): I32 =
  I32(rawSyscall3(SysServiceManagerRegister, 0, 0, 0))


## Invokes the service register syscall wrapper.
proc sysServiceRegister*(kind: U32, pid: I32): I32 =
  I32(rawSyscall3(SysServiceRegister, U64(kind), U64(pid), 0))


## Invokes the service ready syscall wrapper.
proc sysServiceReady*(kind: U32, pid: I32): I32 =
  I32(rawSyscall3(SysServiceReady, U64(kind), U64(pid), 0))


## Invokes the service unregister syscall wrapper.
proc sysServiceUnregister*(kind: U32): I32 =
  I32(rawSyscall3(SysServiceUnregister, U64(kind), 0, 0))


## Invokes the service list syscall wrapper.
proc sysServiceList*(entries: ptr SysServiceInfo, maxEntries: U64): I32 =
  I32(rawSyscall3(SysServiceList, cast[U64](entries), maxEntries, 0))
