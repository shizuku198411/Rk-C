## Centralizes syscall capability checks for user processes and services.
import ../../lib/syscall_ids
import ../../lib/syscall_caps
import ../../lib/types
import ../service/registry
import ../task/process


## Implements the current is user process kernel helper.
proc currentIsUserProcess*(): bool =
  currentProc != nil and currentProc.user.active


## Implements the current has cap kernel helper.
proc currentHasCap*(capability: U32): bool =
  currentIsUserProcess() and (currentProc.user.capabilityMask and capability) == capability


## Implements the current is service manager kernel helper.
proc currentIsServiceManager*(): bool =
  currentIsService(serviceManager)


## Implements the current is block service kernel helper.
proc currentIsBlockService*(): bool =
  currentIsService(serviceBlock)


## Implements the current is fs service kernel helper.
proc currentIsFsService*(): bool =
  currentIsService(serviceFs)


## Implements the current is process service kernel helper.
proc currentIsProcessService*(): bool =
  currentIsService(serviceProcess)


## Implements the current is net service kernel helper.
proc currentIsNetService*(): bool =
  currentIsService(serviceNet)


## Implements the current is proc fs service kernel helper.
proc currentIsProcFsService*(): bool =
  currentIsService(serviceProcFs)


## Implements the fs service available kernel helper.
proc fsServiceAvailable*(): bool =
  serviceAvailable(serviceFs)


## Implements the block service available kernel helper.
proc blockServiceAvailable*(): bool =
  serviceAvailable(serviceBlock)


## Checks whether syscall fs service register is allowed.
proc canSyscallFsServiceRegister*(): bool =
  currentIsUserProcess() and currentHasCap(SysCapRawFs) and not currentIsFsService() and
    not serviceRegistered(serviceManager)


## Checks whether syscall fs service receive is allowed.
proc canSyscallFsServiceReceive*(): bool =
  currentIsFsService() and currentHasCap(SysCapRawFs)


## Checks whether syscall fs service reply is allowed.
proc canSyscallFsServiceReply*(): bool =
  currentIsFsService() and currentHasCap(SysCapRawFs)


## Checks whether syscall raw fs is allowed.
proc canSyscallRawFs*(): bool =
  currentIsFsService() and currentHasCap(SysCapRawFs)


## Checks whether fallback to raw fs is allowed.
proc canFallbackToRawFs*(): bool =
  not serviceRegistered(serviceFs) or canSyscallRawFs()


## Checks whether syscall block service register is allowed.
proc canSyscallBlockServiceRegister*(): bool =
  currentIsUserProcess() and currentHasCap(SysCapRawBlock) and
    not currentIsBlockService() and
    not serviceRegistered(serviceManager)


## Checks whether syscall block service receive is allowed.
proc canSyscallBlockServiceReceive*(): bool =
  currentIsBlockService() and currentHasCap(SysCapRawBlock)


## Checks whether syscall block service reply is allowed.
proc canSyscallBlockServiceReply*(): bool =
  currentIsBlockService() and currentHasCap(SysCapRawBlock)


## Checks whether syscall raw block is allowed.
proc canSyscallRawBlock*(): bool =
  currentIsBlockService() and currentHasCap(SysCapRawBlock)


## Checks whether fallback to raw block is allowed.
proc canFallbackToRawBlock*(): bool =
  not serviceRegistered(serviceBlock) or canSyscallRawBlock()


## Checks whether syscall raw net is allowed.
proc canSyscallRawNet*(): bool =
  currentIsNetService() and currentHasCap(SysCapRawNet)


## Checks whether syscall process list is allowed.
proc canSyscallProcessList*(): bool =
  currentHasCap(SysCapProcessList) and (
    currentIsServiceManager() or currentIsProcessService() or
    currentIsProcFsService()
  )


## Checks whether syscall kill process is allowed.
proc canSyscallKillProcess*(): bool =
  currentHasCap(SysCapProcessKill) and (
    currentIsServiceManager() or currentIsProcessService()
  )


## Checks whether syscall kill target is allowed.
proc canSyscallKillTarget*(pid: int32): bool =
  if pid <= 1:
    return false
  if not canSyscallKillProcess():
    return false
  if isServicePid(pid) and not currentIsServiceManager():
    return false

  true


## Checks whether syscall service manager register is allowed.
proc canSyscallServiceManagerRegister*(): bool =
  if not currentIsUserProcess():
    return false
  if not currentHasCap(SysCapServiceManager):
    return false
  if serviceRegistered(serviceManager) and not currentIsServiceManager():
    return false

  true


## Checks whether syscall service mutation is allowed.
proc canSyscallServiceMutation*(): bool =
  currentIsServiceManager() and currentHasCap(SysCapServiceManager)


## Checks whether syscall service kind mutation is allowed.
proc canSyscallServiceKindMutation*(kind: ServiceKind): bool =
  canSyscallServiceMutation() and kind != serviceManager


## Checks whether syscall trace ctl is allowed.
proc canSyscallTraceCtl*(): bool =
  currentHasCap(SysCapTrace)


## Checks whether syscall shutdown is allowed.
proc canSyscallShutdown*(): bool =
  currentHasCap(SysCapShutdown)


## Checks whether syscall by number is allowed.
proc canSyscallByNumber*(num: U64): bool =
  case num
  of SysPs, SysFdList:
    canSyscallProcessList()
  of SysKill:
    canSyscallKillProcess()
  of SysFsServiceRegister:
    canSyscallFsServiceRegister()
  of SysFsServiceReceive:
    canSyscallFsServiceReceive()
  of SysFsServiceReply:
    canSyscallFsServiceReply()
  of SysRawLs, SysRawMkdir, SysRawUnlink, SysRawRmdir, SysRawReadFile,
      SysRawWriteFile, SysRawFileSize, SysRawReadRange, SysRawRename,
      SysRawChmod, SysRawChown:
    canSyscallRawFs()
  of SysBlockServiceRegister:
    canSyscallBlockServiceRegister()
  of SysBlockServiceReceive:
    canSyscallBlockServiceReceive()
  of SysBlockServiceReply:
    canSyscallBlockServiceReply()
  of SysRawBlockRead, SysRawBlockWrite:
    canSyscallRawBlock()
  of SysServiceManagerRegister:
    canSyscallServiceManagerRegister()
  of SysServiceRegister, SysServiceUnregister, SysServiceReady:
    canSyscallServiceMutation()
  of SysRawNetInfo, SysRawNetInit, SysRawNetMac, SysRawNetRecv,
      SysRawNetSend:
    canSyscallRawNet()
  of SysTraceCtl:
    canSyscallTraceCtl()
  of SysShutdown:
    canSyscallShutdown()
  else:
    true
