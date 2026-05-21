## Provides userland wrappers around raw syscall invocations.
import ../../../lib/syscall_ids
import ../../../lib/syscall_types

export syscall_types

type
  U8* = uint8
  U16* = uint16
  U32* = uint32
  U64* = uint64
  I32* = int32
  I64* = int64

const
  DirEntryNameMax* = 16
  DirEntryTypeFile* = U32(1)
  DirEntryTypeDir* = U32(2)
  DirEntryTypeMount* = U32(3)

  TraceOff* = U64(0)
  TraceOn*  = U64(1)
  TracePid* = U64(2)
  TraceVerbose* = U64(3)


type
  DirEntry* {.packed.} = object
    typ*: U32
    size*: U32
    uid*: U32
    gid*: U32
    mode*: U32
    name*: array[DirEntryNameMax, char]


## Imports the assembly raw syscall entry point.
proc rawSyscall3(num, arg0, arg1, arg2: U64): U64 {.importc: "user_raw_syscall3", cdecl.}


## Stops execution when a noreturn syscall unexpectedly returns.
proc halt() {.noreturn.} =
  while true:
    asm "wfi"


## Invokes the write syscall wrapper.
proc sysWrite*(buf: pointer, len: U64): U64 =
  rawSyscall3(SysWrite, cast[U64](buf), len, 0)


## Invokes the read syscall wrapper.
proc sysRead*(buf: pointer, len: U64): U64 =
  rawSyscall3(SysRead, cast[U64](buf), len, 0)


## Invokes the ps syscall wrapper.
proc sysPs*(entries: ptr SysProcessInfo, maxEntries: U64, flags: U64 = 0): I32 =
  I32(rawSyscall3(SysPs, cast[U64](entries), maxEntries, flags))


## Invokes the ticks syscall wrapper.
proc sysTicks*(): U64 =
  rawSyscall3(SysTicks, 0, 0, 0)


## Invokes the cpu info syscall wrapper.
proc sysCpuInfo*(info: ptr SysCpuInfo): I32 =
  I32(rawSyscall3(SysCpuInfo, cast[U64](info), 0, 0))


## Invokes the kmsg syscall wrapper.
proc sysKmsg*(buf: pointer, capacity: U64): I32 =
  I32(rawSyscall3(SysKmsg, cast[U64](buf), capacity, 0))


## Invokes the traps syscall wrapper.
proc sysTraps*(entries: ptr SysTrapCount): U64 =
  rawSyscall3(SysTraps, cast[U64](entries), 0, 0)

## Invokes the exit syscall wrapper.
proc sysExit*(status: U64) {.noreturn.} =
  discard rawSyscall3(SysExit, status, 0, 0)
  halt()


## Invokes the ls syscall wrapper.
proc sysLs*(path: cstring, entries: ptr DirEntry, maxEntries: U64): I32 =
  I32(rawSyscall3(SysLs, cast[U64](path), cast[U64](entries), maxEntries))


## Packs ls limit offset.
proc packLsLimitOffset(maxEntries, offset: U64): U64 =
  ((offset and U64(0xffffffff'u64)) shl U64(32)) or
    (maxEntries and U64(0xffffffff'u64))


## Invokes the ls at syscall wrapper.
proc sysLsAt*(path: cstring, entries: ptr DirEntry, maxEntries, offset: U64): I32 =
  I32(rawSyscall3(SysLs, cast[U64](path), cast[U64](entries), packLsLimitOffset(maxEntries, offset)))


## Invokes the mkdir syscall wrapper.
proc sysMkdir*(path: cstring): I32 =
  I32(rawSyscall3(SysMkdir, cast[U64](path), 0, 0))


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


## Invokes the unlink syscall wrapper.
proc sysUnlink*(path: cstring): I32 =
  I32(rawSyscall3(SysUnlink, cast[U64](path), 0, 0))


## Invokes the rmdir syscall wrapper.
proc sysRmdir*(path: cstring): I32 =
  I32(rawSyscall3(SysRmdir, cast[U64](path), 0, 0))


## Invokes the shutdown syscall wrapper.
proc sysShutdown*(): I32 =
  I32(rawSyscall3(SysShutdown, 0, 0, 0))


## Invokes the get date time syscall wrapper.
proc sysGetDateTime*(dt: ptr SysDateTime): I32 =
  I32(rawSyscall3(SysGetDateTime, cast[U64](dt), 0, 0))


## Invokes the read file syscall wrapper.
proc sysReadFile*(path: cstring, buf: pointer, capacity: U64): I32 =
  I32(rawSyscall3(SysReadFile, cast[U64](path), cast[U64](buf), capacity))


## Invokes the write file syscall wrapper.
proc sysWriteFile*(path: cstring, buf: pointer, size: U64): I32 =
  I32(rawSyscall3(SysWriteFile, cast[U64](path), cast[U64](buf), size))


## Packs write size flags.
proc packWriteSizeFlags(size: U64, flags: U32): U64 =
  (U64(flags) shl U64(32)) or size


## Invokes the write file mode syscall wrapper.
proc sysWriteFileMode*(path: cstring, buf: pointer, size: U64, flags: U32): I32 =
  I32(rawSyscall3(SysWriteFile, cast[U64](path), cast[U64](buf), packWriteSizeFlags(size, flags)))


## Invokes the rename syscall wrapper.
proc sysRename*(oldPath, newPath: cstring): I32 =
  I32(rawSyscall3(SysRename, cast[U64](oldPath), cast[U64](newPath), 0))


## Invokes the open syscall wrapper.
proc sysOpen*(path: cstring, flags: U32): I32 =
  I32(rawSyscall3(SysOpen, cast[U64](path), U64(flags), 0))


## Invokes the read fd syscall wrapper.
proc sysReadFd*(fd: I32, buf: pointer, len: U64): I32 =
  I32(rawSyscall3(SysReadFd, U64(fd), cast[U64](buf), len))


## Invokes the write fd syscall wrapper.
proc sysWriteFd*(fd: I32, buf: pointer, len: U64): I32 =
  I32(rawSyscall3(SysWriteFd, U64(fd), cast[U64](buf), len))


## Invokes the close syscall wrapper.
proc sysClose*(fd: I32): I32 =
  I32(rawSyscall3(SysClose, U64(fd), 0, 0))


## Invokes the lseek syscall wrapper.
proc sysLseek*(fd: I32, offset: I64, whence: U32): I32 =
  I32(rawSyscall3(SysLseek, U64(fd), U64(offset), U64(whence)))


## Invokes the pipe syscall wrapper.
proc sysPipe*(fds: ptr I32): I32 =
  I32(rawSyscall3(SysPipe, cast[U64](fds), 0, 0))


## Invokes the dup2 syscall wrapper.
proc sysDup2*(oldFd, newFd: I32): I32 =
  I32(rawSyscall3(SysDup2, U64(oldFd), U64(newFd), 0))


## Invokes the poll syscall wrapper.
proc sysPoll*(events: ptr SysPollEvent, count: U64, timeoutTicks: U64): I32 =
  I32(rawSyscall3(SysPoll, cast[U64](events), count, timeoutTicks))


## Invokes the get cwd syscall wrapper.
proc sysGetCwd*(buf: pointer, capacity: U64): I32 =
  I32(rawSyscall3(SysGetCwd, cast[U64](buf), capacity, 0))


## Invokes the set cwd syscall wrapper.
proc sysSetCwd*(path: cstring): I32 =
  I32(rawSyscall3(SysSetCwd, cast[U64](path), 0, 0))


## Invokes the get bit map syscall wrapper.
proc sysGetBitMap*(info: ptr SysBitmapInfo): I32 =
  I32(rawSyscall3(SysGetBitMap, cast[U64](info), 0, 0))


## Invokes the fs info syscall wrapper.
proc sysFsInfo*(entries: ptr SysFsInfoEntry, maxEntries: U64): I32 =
  I32(rawSyscall3(SysFsInfo, cast[U64](entries), maxEntries, 0))


## Invokes the ipc send syscall wrapper.
proc sysIpcSend*(pid: I32, msg: cstring): I32 =
  I32(rawSyscall3(SysIpcSend, U64(pid), cast[U64](msg), 0))


## Invokes the ipc receive syscall wrapper.
proc sysIpcReceive*(msg: ptr SysIpcMessage): I32 =
  I32(rawSyscall3(SysIpcReceive, cast[U64](msg), 0, 0))


## Invokes the ipc try receive syscall wrapper.
proc sysIpcTryReceive*(msg: ptr SysIpcMessage): I32 =
  I32(rawSyscall3(SysIpcTryReceive, cast[U64](msg), 0, 0))


## Invokes the ipc send packet syscall wrapper.
proc sysIpcSendPacket*(pid: I32, packet: ptr SysIpcPacket): I32 =
  I32(rawSyscall3(SysIpcSendPacket, U64(pid), cast[U64](packet), 0))


## Invokes the ipc receive packet syscall wrapper.
proc sysIpcReceivePacket*(packet: ptr SysIpcPacket): I32 =
  I32(rawSyscall3(SysIpcReceivePacket, cast[U64](packet), 0, 0))


## Invokes the ipc try receive packet syscall wrapper.
proc sysIpcTryReceivePacket*(packet: ptr SysIpcPacket): I32 =
  I32(rawSyscall3(SysIpcTryReceivePacket, cast[U64](packet), 0, 0))


## Invokes the kill syscall wrapper.
proc sysKill*(pid: I32): I32 =
  I32(rawSyscall3(SysKill, U64(pid), 0, 0))


## Invokes the signal poll syscall wrapper.
proc sysSignalPoll*(signal: ptr U32): I32 =
  I32(rawSyscall3(SysSignalPoll, cast[U64](signal), 0, 0))


## Invokes the fs service register syscall wrapper.
proc sysFsServiceRegister*(): I32 =
  I32(rawSyscall3(SysFsServiceRegister, 0, 0, 0))


## Invokes the fs service receive syscall wrapper.
proc sysFsServiceReceive*(req: ptr SysFsRequest): I32 =
  I32(rawSyscall3(SysFsServiceReceive, cast[U64](req), 0, 0))


## Invokes the fs service reply syscall wrapper.
proc sysFsServiceReply*(resp: ptr SysFsResponse): I32 =
  I32(rawSyscall3(SysFsServiceReply, cast[U64](resp), 0, 0))


## Invokes the raw ls syscall wrapper.
proc sysRawLs*(path: cstring, entries: pointer, maxEntries: U64): I32 =
  I32(rawSyscall3(SysRawLs, cast[U64](path), cast[U64](entries), maxEntries))


## Invokes the raw ls at syscall wrapper.
proc sysRawLsAt*(path: cstring, entries: pointer, maxEntries, offset: U64): I32 =
  I32(rawSyscall3(SysRawLs, cast[U64](path), cast[U64](entries), packLsLimitOffset(maxEntries, offset)))


## Invokes the raw mkdir syscall wrapper.
proc sysRawMkdir*(path: cstring): I32 =
  I32(rawSyscall3(SysRawMkdir, cast[U64](path), 0, 0))


## Invokes the raw unlink syscall wrapper.
proc sysRawUnlink*(path: cstring): I32 =
  I32(rawSyscall3(SysRawUnlink, cast[U64](path), 0, 0))


## Invokes the raw rmdir syscall wrapper.
proc sysRawRmdir*(path: cstring): I32 =
  I32(rawSyscall3(SysRawRmdir, cast[U64](path), 0, 0))


## Invokes the raw read file syscall wrapper.
proc sysRawReadFile*(path: cstring, buf: pointer, capacity: U64): I32 =
  I32(rawSyscall3(SysRawReadFile, cast[U64](path), cast[U64](buf), capacity))


## Invokes the raw write file syscall wrapper.
proc sysRawWriteFile*(path: cstring, buf: pointer, size: U64): I32 =
  I32(rawSyscall3(SysRawWriteFile, cast[U64](path), cast[U64](buf), size))


## Invokes the raw write file mode syscall wrapper.
proc sysRawWriteFileMode*(path: cstring, buf: pointer, size: U64, flags: U32): I32 =
  I32(rawSyscall3(SysRawWriteFile, cast[U64](path), cast[U64](buf), packWriteSizeFlags(size, flags)))


## Invokes the raw rename syscall wrapper.
proc sysRawRename*(oldPath, newPath: cstring): I32 =
  I32(rawSyscall3(SysRawRename, cast[U64](oldPath), cast[U64](newPath), 0))


## Invokes the raw chmod syscall wrapper.
proc sysRawChmod*(path: cstring, mode: U32): I32 =
  I32(rawSyscall3(SysRawChmod, cast[U64](path), U64(mode), 0))


## Invokes the raw chown syscall wrapper.
proc sysRawChown*(path: cstring, uid, gid: U32): I32 =
  let uidGid = U64(uid) or (U64(gid) shl U64(32))
  I32(rawSyscall3(SysRawChown, cast[U64](path), uidGid, 0))


## Invokes the raw file size syscall wrapper.
proc sysRawFileSize*(path: cstring): I32 =
  I32(rawSyscall3(SysRawFileSize, cast[U64](path), 0, 0))


## Invokes the raw read range syscall wrapper.
proc sysRawReadRange*(req: ptr SysFsRequest): I32 =
  I32(rawSyscall3(SysRawReadRange, cast[U64](req), 0, 0))


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


## Invokes the yield syscall wrapper.
proc sysYield*(): I32 =
  I32(rawSyscall3(SysYield, 0, 0, 0))


## Invokes the sleep syscall wrapper.
proc sysSleep*(ticks: U64): I32 =
  I32(rawSyscall3(SysSleep, ticks, 0, 0))


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


## Invokes the chmod syscall wrapper.
proc sysChmod*(path: cstring, mode: U32): I32 =
  I32(rawSyscall3(SysChmod, cast[U64](path), U64(mode), 0))


## Invokes the chown syscall wrapper.
proc sysChown*(path: cstring, uid, gid: U32): I32 =
  let uidGid = U64(uid) or (U64(gid) shl U64(32))
  I32(rawSyscall3(SysChown, cast[U64](path), uidGid, 0))


## Invokes the last error syscall wrapper.
proc sysLastError*(): I32 =
  I32(rawSyscall3(SysLastError, 0, 0, 0))


## Invokes the raw net info syscall wrapper.
proc sysRawNetInfo*(info: ptr SysNetDeviceInfo): I32 =
  I32(rawSyscall3(SysRawNetInfo, cast[U64](info), 0, 0))


## Invokes the raw net init syscall wrapper.
proc sysRawNetInit*(): I32 =
  I32(rawSyscall3(SysRawNetInit, 0, 0, 0))


## Invokes the raw net mac syscall wrapper.
proc sysRawNetMac*(mac: pointer): I32 =
  I32(rawSyscall3(SysRawNetMac, cast[U64](mac), 0, 0))


## Invokes the raw net recv syscall wrapper.
proc sysRawNetRecv*(buf: pointer, capacity: U64): I32 =
  I32(rawSyscall3(SysRawNetRecv, cast[U64](buf), capacity, 0))


## Invokes the raw net send syscall wrapper.
proc sysRawNetSend*(buf: pointer, size: U64): I32 =
  I32(rawSyscall3(SysRawNetSend, cast[U64](buf), size, 0))


## Invokes the trace ctl syscall wrapper.
proc sysTraceCtl*(cmd: U64, value: U64): I32 =
  I32(rawSyscall3(SysTraceCtl, cmd, value, 0))


## Invokes the entropy syscall wrapper.
proc sysEntropy*(buf: pointer, size: U64): I32 =
  I32(rawSyscall3(SysEntropy, cast[U64](buf), size, 0))


## Invokes the get cap syscall wrapper.
proc sysGetCap*(buf: pointer, size: U64): I32 =
  I32(rawSyscall3(SysGetCap, cast[U64](buf), size, 0))
