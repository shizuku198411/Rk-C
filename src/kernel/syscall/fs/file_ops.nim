## Implements file, directory, descriptor, and pipe syscall handlers.
import ../../../lib/types
import ../../../lib/syscall_types
import ../../../lib/calc
import ../../../lib/fs_permissions
import ../../../lib/user_ids
import ../../dev/timer
import ../../dev/tty
import ../../fs/fs
import ../../lib/fd_helpers
import ../../lib/user_path
import ../../syscall/fs/fs_service_ops
import ../../syscall/io/tty_ops
import ../../mm/usercopy
import ../../task/process
import ../scratch

const
  SysDirEntryMax = SysScratchDirEntryMax
  SysFileIoMax = SysScratchFileIoMax
  KnownOpenFlags = SysOpenRead or SysOpenWrite or SysOpenCreate or
    SysOpenTrunc or SysOpenAppend
  KnownPollEvents = SysPollFdRead or SysPollFdWrite or SysPollIpcRead or
    SysPollPidExit or SysPollTimer

template pathBuf: untyped = fsScratch.pathBuf
template fileBuf: untyped = fsScratch.fileBuf
template fdFileBuf: untyped = fsScratch.fdFileBuf
template pollEvents: untyped = fsScratch.pollEvents
template renamePathBuf: untyped = fsScratch.renamePathBuf


## Includes handles path-oriented filesystem syscalls and access checks.
include ./internal/path_ops


## Includes handles open file descriptors, pipes, duplicate descriptors, and seek.
include ./internal/fd_ops


## Includes evaluates descriptor readiness and implements poll waits.
include ./internal/poll_ops
