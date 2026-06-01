## Provides wrappers for process and user identity syscalls.
import ./base
import ../../../lib/syscall_ids


## Invokes the ps syscall wrapper.
proc sysPs*(entries: ptr SysProcessInfo, maxEntries: U64, flags: U64 = 0): I32 =
  I32(rawSyscall3(SysPs, cast[U64](entries), maxEntries, flags))


## Invokes the exec syscall wrapper.
proc sysExec*(path: cstring, arg: cstring, detached: bool = false): I32 =
  let detachedVal =
    if detached:
      U64(1)
    else:
      U64(0)

  I32(rawSyscall3(SysExec, cast[U64](path), cast[U64](arg), detachedVal))


## Invokes the exec as syscall wrapper.
proc sysExecAs*(path: cstring, arg: cstring, uid, gid: U32): I32 =
  let uidGid = U64(uid) or (U64(gid) shl U64(32))
  I32(rawSyscall3(SysExecAs, cast[U64](path), cast[U64](arg), uidGid))


## Invokes the wait syscall wrapper.
proc sysWait*(pid: I32): U64 =
  rawSyscall3(SysWait, U64(pid), 0, 0)


## Invokes the kill syscall wrapper.
proc sysKill*(pid: I32): I32 =
  I32(rawSyscall3(SysKill, U64(pid), 0, 0))


## Invokes the get bit map syscall wrapper.
proc sysGetBitMap*(info: ptr SysBitmapInfo): I32 =
  I32(rawSyscall3(SysGetBitMap, cast[U64](info), 0, 0))


## Invokes the brk syscall wrapper.
proc sysBrk*(newEnd: U64): I64 =
  I64(rawSyscall3(SysBrk, newEnd, 0, 0))


## Invokes the sbrk syscall wrapper.
proc sysSbrk*(delta: I64): I64 =
  I64(rawSyscall3(SysSbrk, U64(delta), 0, 0))


## Invokes the get pid syscall wrapper.
proc sysGetPid*(): I32 =
  I32(rawSyscall3(SysGetPid, 0, 0, 0))


## Invokes the get ppid syscall wrapper.
proc sysGetPpid*(): I32 =
  I32(rawSyscall3(SysGetPpid, 0, 0, 0))


## Invokes the get uid syscall wrapper.
proc sysGetUid*(): U32 =
  U32(rawSyscall3(SysGetUid, 0, 0, 0))


## Invokes the get gid syscall wrapper.
proc sysGetGid*(): U32 =
  U32(rawSyscall3(SysGetGid, 0, 0, 0))


## Invokes the set user syscall wrapper.
proc sysSetUser*(uid, gid: U32): I32 =
  I32(rawSyscall3(SysSetUser, U64(uid), U64(gid), 0))
