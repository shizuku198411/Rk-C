## Implements filesystem service registration and request/reply syscall handlers.
import ../../../lib/fixed_string
import ../../../lib/mem
import ../../../lib/syscall_types
import ../../../lib/types
import ../../fs/dirent
import ../../fs/fs
import ../../lib/user_path
import ../../mm/usercopy
import ../../service/registry
import ../ipc/request_reply
import ../syscall_cap
import ../../task/process

const
  FsPendingMax = 8
  FsRawDirEntryMax = 32

type
  PendingFsRequest = object
    ipc: IpcPending
    request: SysFsRequest
    response: SysFsResponse

var
  requestDomain: IpcRequestDomain
  pending: array[FsPendingMax, PendingFsRequest]
  rawEntries: array[FsRawDirEntryMax, FsDirEntry]
  rawFileBuf: array[SysFsDataMax, U8]
  renamePathBuf: array[SysFsPathMax, char]


## Includes shared filesystem service request and response validation helpers.
include ./internal/fs_request_validation


## Includes manages filesystem service request queues and registration syscalls.
include ./internal/fs_transport


## Includes forwards filesystem operations through the registered filesystem service.
include ./internal/fs_mediated_ops


## Includes handles privileged raw filesystem access used by the service process.
include ./internal/fs_raw_ops
