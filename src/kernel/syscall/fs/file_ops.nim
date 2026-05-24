## Implements file, directory, descriptor, and pipe syscall handlers.
import ../../../lib/types
import ../../../lib/syscall_types
import ../../../lib/calc
import ../../../lib/fs_permissions
import ../../../lib/user_ids
import ../../dev/timer
import ../../fs/fs
import ../../lib/fd_helpers
import ../../syscall/fs/fs_service_ops
import ../../syscall/io/console_io
import ../../mm/usercopy
import ../../task/process

const
  SysPathMax = U64(128)
  SysDirEntryMax = U64(32)
  SysFileIoMax = U64(4096)
  KnownPollEvents = SysPollFdRead or SysPollFdWrite or SysPollIpcRead or
    SysPollPidExit or SysPollTimer

var
  pathBuf: array[SysPathMax, char]
  fileBuf: array[SysFileIoMax, U8]
  fdFileBuf: array[SysFileIoMax, U8]
  pollEvents: array[SysPollMaxEvents, SysPollEvent]
  renamePathBuf: array[SysPathMax, char]


## Includes handles path-oriented filesystem syscalls and access checks.
include ./internal/path_ops


## Includes handles open file descriptors, pipes, duplicate descriptors, and seek.
include ./internal/fd_ops


## Includes evaluates descriptor readiness and implements poll waits.
include ./internal/poll_ops
