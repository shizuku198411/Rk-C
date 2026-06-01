## Provides wrappers for filesystem, descriptor, and raw filesystem syscalls.
import ./base
import ../../../lib/syscall_ids

const
  DirEntryNameMax* = 16
  DirEntryTypeFile* = U32(1)
  DirEntryTypeDir* = U32(2)
  DirEntryTypeMount* = U32(3)


type
  DirEntry* {.packed.} = object
    typ*: U32
    size*: U32
    uid*: U32
    gid*: U32
    mode*: U32
    name*: array[DirEntryNameMax, char]


## Packs ls limit offset.
proc packLsLimitOffset*(maxEntries, offset: U64): U64 =
  ((offset and U64(0xffffffff'u64)) shl U64(32)) or
    (maxEntries and U64(0xffffffff'u64))


## Packs write size flags.
proc packWriteSizeFlags*(size: U64, flags: U32): U64 =
  (U64(flags) shl U64(32)) or size


## Invokes the ls syscall wrapper.
proc sysLs*(path: cstring, entries: ptr DirEntry, maxEntries: U64): I32 =
  I32(rawSyscall3(SysLs, cast[U64](path), cast[U64](entries), maxEntries))


## Invokes the ls at syscall wrapper.
proc sysLsAt*(path: cstring, entries: ptr DirEntry, maxEntries, offset: U64): I32 =
  I32(rawSyscall3(SysLs, cast[U64](path), cast[U64](entries), packLsLimitOffset(maxEntries, offset)))


## Invokes the mkdir syscall wrapper.
proc sysMkdir*(path: cstring): I32 =
  I32(rawSyscall3(SysMkdir, cast[U64](path), 0, 0))


## Invokes the unlink syscall wrapper.
proc sysUnlink*(path: cstring): I32 =
  I32(rawSyscall3(SysUnlink, cast[U64](path), 0, 0))


## Invokes the rmdir syscall wrapper.
proc sysRmdir*(path: cstring): I32 =
  I32(rawSyscall3(SysRmdir, cast[U64](path), 0, 0))


## Invokes the read file syscall wrapper.
proc sysReadFile*(path: cstring, buf: pointer, capacity: U64): I32 =
  I32(rawSyscall3(SysReadFile, cast[U64](path), cast[U64](buf), capacity))


## Invokes the write file syscall wrapper.
proc sysWriteFile*(path: cstring, buf: pointer, size: U64): I32 =
  I32(rawSyscall3(SysWriteFile, cast[U64](path), cast[U64](buf), size))


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


## Invokes the get cwd syscall wrapper.
proc sysGetCwd*(buf: pointer, capacity: U64): I32 =
  I32(rawSyscall3(SysGetCwd, cast[U64](buf), capacity, 0))


## Invokes the set cwd syscall wrapper.
proc sysSetCwd*(path: cstring): I32 =
  I32(rawSyscall3(SysSetCwd, cast[U64](path), 0, 0))


## Invokes the fs info syscall wrapper.
proc sysFsInfo*(entries: ptr SysFsInfoEntry, maxEntries: U64): I32 =
  I32(rawSyscall3(SysFsInfo, cast[U64](entries), maxEntries, 0))


## Invokes the chmod syscall wrapper.
proc sysChmod*(path: cstring, mode: U32): I32 =
  I32(rawSyscall3(SysChmod, cast[U64](path), U64(mode), 0))


## Invokes the chown syscall wrapper.
proc sysChown*(path: cstring, uid, gid: U32): I32 =
  let uidGid = U64(uid) or (U64(gid) shl U64(32))
  I32(rawSyscall3(SysChown, cast[U64](path), uidGid, 0))


## Invokes the fd list syscall wrapper.
proc sysFdList*(pid: I32, entries: ptr SysFdInfo, maxEntries: U64): I32 =
  I32(rawSyscall3(SysFdList, U64(pid), cast[U64](entries), maxEntries))


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


## Invokes the raw write range syscall wrapper.
proc sysRawWriteRange*(req: ptr SysFsRequest): I32 =
  I32(rawSyscall3(SysRawWriteRange, cast[U64](req), 0, 0))
