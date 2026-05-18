import ../../lib/syscall_ids
import ../../lib/syscall_caps
import ../../lib/types
import ../service/registry
import ../task/process


proc currentIsUserProcess*(): bool =
  currentProc != nil and currentProc.user.active


proc currentHasCap*(capability: U32): bool =
  currentIsUserProcess() and (currentProc.user.capabilityMask and capability) == capability


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
  currentIsUserProcess() and currentHasCap(SysCapRawFs) and not currentIsFsService() and
    not serviceRegistered(serviceManager)


proc canSyscallFsServiceReceive*(): bool =
  currentIsFsService() and currentHasCap(SysCapRawFs)


proc canSyscallFsServiceReply*(): bool =
  currentIsFsService() and currentHasCap(SysCapRawFs)


proc canSyscallRawFs*(): bool =
  currentIsFsService() and currentHasCap(SysCapRawFs)


proc canFallbackToRawFs*(): bool =
  not serviceRegistered(serviceFs) or canSyscallRawFs()


proc canSyscallBlockServiceRegister*(): bool =
  currentIsUserProcess() and currentHasCap(SysCapRawBlock) and
    not currentIsBlockService() and
    not serviceRegistered(serviceManager)


proc canSyscallBlockServiceReceive*(): bool =
  currentIsBlockService() and currentHasCap(SysCapRawBlock)


proc canSyscallBlockServiceReply*(): bool =
  currentIsBlockService() and currentHasCap(SysCapRawBlock)


proc canSyscallRawBlock*(): bool =
  currentIsBlockService() and currentHasCap(SysCapRawBlock)


proc canFallbackToRawBlock*(): bool =
  not serviceRegistered(serviceBlock) or canSyscallRawBlock()


proc canSyscallRawNet*(): bool =
  currentIsNetService() and currentHasCap(SysCapRawNet)


proc canSyscallProcessList*(): bool =
  currentHasCap(SysCapProcessList) and (
    currentIsServiceManager() or currentIsProcessService() or
    currentIsProcFsService()
  )


proc canSyscallKillProcess*(): bool =
  currentHasCap(SysCapProcessKill) and (
    currentIsServiceManager() or currentIsProcessService()
  )


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
  if not currentHasCap(SysCapServiceManager):
    return false
  if serviceRegistered(serviceManager) and not currentIsServiceManager():
    return false

  true


proc canSyscallServiceMutation*(): bool =
  currentIsServiceManager() and currentHasCap(SysCapServiceManager)


proc canSyscallServiceKindMutation*(kind: ServiceKind): bool =
  canSyscallServiceMutation() and kind != serviceManager


proc canSyscallTraceCtl*(): bool =
  currentHasCap(SysCapTrace)


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
  of SysTraceCtl:
    canSyscallTraceCtl()
  else:
    true
