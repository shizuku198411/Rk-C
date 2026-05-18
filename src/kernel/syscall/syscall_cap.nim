import ../../lib/syscall_ids
import ../../lib/types
import ../service/registry
import ../task/process


proc currentIsUserProcess*(): bool =
  currentProc != nil and currentProc.user.active


proc currentIsServiceManager*(): bool =
  currentIsService(serviceManager)


proc currentIsBlockService*(): bool =
  currentIsService(serviceBlock)


proc currentIsFsService*(): bool =
  currentIsService(serviceFs)


proc currentIsProcessService*(): bool =
  currentIsService(serviceProcess)


proc currentIsNetService*(): bool =
  currentIsService(serviceNet)


proc currentIsProcFsService*(): bool =
  currentIsService(serviceProcFs)


proc fsServiceAvailable*(): bool =
  serviceAvailable(serviceFs)


proc blockServiceAvailable*(): bool =
  serviceAvailable(serviceBlock)


proc canSyscallFsServiceRegister*(): bool =
  currentIsUserProcess() and not currentIsFsService() and
    not serviceRegistered(serviceManager)


proc canSyscallFsServiceReceive*(): bool =
  currentIsFsService()


proc canSyscallFsServiceReply*(): bool =
  currentIsFsService()


proc canSyscallRawFs*(): bool =
  currentIsFsService()


proc canFallbackToRawFs*(): bool =
  not serviceRegistered(serviceFs) or currentIsFsService()


proc canSyscallBlockServiceRegister*(): bool =
  currentIsUserProcess() and not currentIsBlockService() and
    not serviceRegistered(serviceManager)


proc canSyscallBlockServiceReceive*(): bool =
  currentIsBlockService()


proc canSyscallBlockServiceReply*(): bool =
  currentIsBlockService()


proc canSyscallRawBlock*(): bool =
  currentIsBlockService()


proc canFallbackToRawBlock*(): bool =
  not serviceRegistered(serviceBlock) or currentIsBlockService()


proc canSyscallRawNet*(): bool =
  currentIsNetService()


proc canSyscallProcessList*(): bool =
  currentIsServiceManager() or currentIsProcessService() or
    currentIsProcFsService()


proc canSyscallKillProcess*(): bool =
  currentIsServiceManager() or currentIsProcessService()


proc canSyscallKillTarget*(pid: int32): bool =
  if pid <= 1:
    return false
  if not canSyscallKillProcess():
    return false
  if isServicePid(pid) and not currentIsServiceManager():
    return false

  true


proc canSyscallServiceManagerRegister*(): bool =
  if not currentIsUserProcess():
    return false
  if serviceRegistered(serviceManager) and not currentIsServiceManager():
    return false

  true


proc canSyscallServiceMutation*(): bool =
  currentIsServiceManager()


proc canSyscallServiceKindMutation*(kind: ServiceKind): bool =
  canSyscallServiceMutation() and kind != serviceManager


proc canSyscallByNumber*(num: U64): bool =
  case num
  of SysPs:
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
      SysRawWriteFile:
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
  else:
    true
