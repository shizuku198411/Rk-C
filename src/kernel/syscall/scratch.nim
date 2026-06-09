## Shared scratch storage for syscall handlers.
##
## Policy:
## - These buffers are temporary syscall-entry work areas, not durable kernel state.
## - The current kernel is expected to run these handlers non-reentrantly. Do not
##   use this storage from interrupt, panic, or tracing paths.
## - Do not keep pointers into these buffers after returning from a syscall. If a
##   handler can sleep or hand work to another subsystem, copy data into owned
##   kernel/service state before sleeping.
## - New syscall handlers should add fields here instead of introducing ad-hoc
##   module-global scratch buffers.
## - The object boundary is intentional: currentProc-backed handlers can move to
##   per-process scratch later, and SMP can move this storage to per-CPU scratch.
import ../../lib/syscall_types
import ../../lib/types
import ../fs/dirent
import ../mm/usercopy
import ../task/process

const
  SysScratchPathMax* = U64(128)
  SysScratchDirEntryMax* = U64(32)
  SysScratchFileIoMax* = U64(4096)

type
  FsSyscallScratch* = object
    pathBuf*: array[SysScratchPathMax, char]
    fileBuf*: array[SysScratchFileIoMax, U8]
    fdFileBuf*: array[SysScratchFileIoMax, U8]
    pollEvents*: array[SysPollMaxEvents, SysPollEvent]
    renamePathBuf*: array[SysScratchPathMax, char]

  ProcessSyscallScratch* = object
    processEntries*: array[MaxProcs, SysProcessInfo]
    pathBuf*: array[UserCStringMax, char]
    argBuf*: array[UserCStringMax, char]
    cwdCheckEntries*: array[2, FsDirEntry]
    fdInfoEntries*: array[SysFdMax, SysFdInfo]

  IpcSyscallScratch* = object
    sendBuf*: array[SysIpcMessageMax, char]

var
  fsScratch*: FsSyscallScratch
  processScratch*: ProcessSyscallScratch
  ipcScratch*: IpcSyscallScratch
