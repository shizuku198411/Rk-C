import ../../lib/syscall_ids
import ../../lib/syscall_types

export syscall_types

type
  U32* = uint32
  U64* = uint64
  I32* = int32

const
  DirEntryNameMax* = 16
  DirEntryTypeFile* = U32(1)
  DirEntryTypeDir* = U32(2)
  DirEntryTypeMount* = U32(3)

type
  DirEntry* {.packed.} = object
    typ*: U32
    size*: U32
    name*: array[DirEntryNameMax, char]


proc rawSyscall3(num, arg0, arg1, arg2: U64): U64 {.importc: "user_raw_syscall3", cdecl.}


proc halt() {.noreturn.} =
  while true:
    asm "wfi"


proc sysWrite*(buf: pointer, len: U64): U64 =
  rawSyscall3(SysWrite, cast[U64](buf), len, 0)


proc sysRead*(buf: pointer, len: U64): U64 =
  rawSyscall3(SysRead, cast[U64](buf), len, 0)


proc sysPs*(entries: ptr SysProcessInfo, maxEntries: U64): I32 =
  I32(rawSyscall3(SysPs, cast[U64](entries), maxEntries, 0))


proc sysTicks*(): U64 =
  rawSyscall3(SysTicks, 0, 0, 0)


proc sysExit*(status: U64) {.noreturn.} =
  discard rawSyscall3(SysExit, status, 0, 0)
  halt()


proc sysLs*(path: cstring, entries: ptr DirEntry, maxEntries: U64): I32 =
  I32(rawSyscall3(SysLs, cast[U64](path), cast[U64](entries), maxEntries))


proc sysMkdir*(path: cstring): I32 =
  I32(rawSyscall3(SysMkdir, cast[U64](path), 0, 0))


proc sysExec*(path: cstring, arg: cstring, detached: bool = false): I32 =
  let detachedVal =
    if detached:
      U64(1)
    else:
      U64(0)

  I32(rawSyscall3(SysExec, cast[U64](path), cast[U64](arg), detachedVal))


proc sysWait*(pid: I32): U64 =
  rawSyscall3(SysWait, U64(pid), 0, 0)


proc sysUnlink*(path: cstring): I32 =
  I32(rawSyscall3(SysUnlink, cast[U64](path), 0, 0))


proc sysRmdir*(path: cstring): I32 =
  I32(rawSyscall3(SysRmdir, cast[U64](path), 0, 0))


proc sysShutdown*() =
  discard rawSyscall3(SysShutdown, 0, 0, 0)


proc sysGetDateTime*(dt: ptr SysDateTime): I32 =
  I32(rawSyscall3(SysGetDateTime, cast[U64](dt), 0, 0))


proc sysReadFile*(path: cstring, buf: pointer, capacity: U64): I32 =
  I32(rawSyscall3(SysReadFile, cast[U64](path), cast[U64](buf), capacity))


proc sysWriteFile*(path: cstring, buf: pointer, size: U64): I32 =
  I32(rawSyscall3(SysWriteFile, cast[U64](path), cast[U64](buf), size))


proc sysGetCwd*(buf: pointer, capacity: U64): I32 =
  I32(rawSyscall3(SysGetCwd, cast[U64](buf), capacity, 0))


proc sysSetCwd*(path: cstring): I32 =
  I32(rawSyscall3(SysSetCwd, cast[U64](path), 0, 0))


proc sysGetBitMap*(info: ptr SysBitmapInfo): I32 =
  I32(rawSyscall3(SysGetBitMap, cast[U64](info), 0, 0))


proc sysIpcSend*(pid: I32, msg: cstring): I32 =
  I32(rawSyscall3(SysIpcSend, U64(pid), cast[U64](msg), 0))


proc sysIpcReceive*(msg: ptr SysIpcMessage): I32 =
  I32(rawSyscall3(SysIpcReceive, cast[U64](msg), 0, 0))


proc sysKill*(pid: I32): I32 =
  I32(rawSyscall3(SysKill, U64(pid), 0, 0))


proc sysFsServiceRegister*(): I32 =
  I32(rawSyscall3(SysFsServiceRegister, 0, 0, 0))


proc sysFsServiceReceive*(req: ptr SysFsRequest): I32 =
  I32(rawSyscall3(SysFsServiceReceive, cast[U64](req), 0, 0))


proc sysFsServiceReply*(resp: ptr SysFsResponse): I32 =
  I32(rawSyscall3(SysFsServiceReply, cast[U64](resp), 0, 0))


proc sysRawLs*(path: cstring, entries: pointer, maxEntries: U64): I32 =
  I32(rawSyscall3(SysRawLs, cast[U64](path), cast[U64](entries), maxEntries))


proc sysRawMkdir*(path: cstring): I32 =
  I32(rawSyscall3(SysRawMkdir, cast[U64](path), 0, 0))


proc sysRawUnlink*(path: cstring): I32 =
  I32(rawSyscall3(SysRawUnlink, cast[U64](path), 0, 0))


proc sysRawRmdir*(path: cstring): I32 =
  I32(rawSyscall3(SysRawRmdir, cast[U64](path), 0, 0))


proc sysRawReadFile*(path: cstring, buf: pointer, capacity: U64): I32 =
  I32(rawSyscall3(SysRawReadFile, cast[U64](path), cast[U64](buf), capacity))


proc sysRawWriteFile*(path: cstring, buf: pointer, size: U64): I32 =
  I32(rawSyscall3(SysRawWriteFile, cast[U64](path), cast[U64](buf), size))
