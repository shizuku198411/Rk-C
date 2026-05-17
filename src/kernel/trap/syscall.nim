import ../../lib/syscall_ids
import ../../lib/types
import ../syscall/blk/block_service_ops
import ../syscall/fs/file_ops
import ../syscall/fs/fs_service_ops
import ../syscall/ipc/ipc_ops
import ../syscall/mm/memory_ops
import ../syscall/net/net_ops
import ../syscall/service/service_ops
import ../syscall/system/system_ops
import ../syscall/system/trap_ops
import ../syscall/task/process_ops
import ../trap/trap_types
import ../trap/syscall_trace


proc handleSyscall*(frame: ptr TrapFrame) =
  traceSyscallEnter(frame)

  case frame.a3
  of SysWrite:
    frame.a0 = syscallWriteFd(1, frame.a0, frame.a1)

  of SysRead:
    frame.a0 = syscallReadFd(0, frame.a0, frame.a1)

  of SysPs:
    frame.a0 = syscallPs(frame.a0, frame.a1, frame.a2)

  of SysTicks:
    frame.a0 = syscallTicks()

  of SysCpuInfo:
    frame.a0 = syscallCpuInfo(frame.a0)
  
  of SysTraps:
    frame.a0 = syscallTrapCount(frame.a0)

  of SysExit:
    frame.a0 = syscallExit(frame.a0)

  of SysLs:
    frame.a0 = syscallLs(frame.a0, frame.a1, frame.a2)

  of SysMkdir:
    frame.a0 = syscallMkdir(frame.a0)

  of SysExec:
    frame.a0 = syscallExec(frame.a0, frame.a1, frame.a2)

  of SysWait:
    frame.a0 = syscallWait(frame.a0)

  of SysUnlink:
    frame.a0 = syscallUnlink(frame.a0)

  of SysRmdir:
    frame.a0 = syscallRmdir(frame.a0)

  of SysShutdown:
    frame.a0 = syscallShutdown()

  of SysYield:
    frame.a0 = syscallYield()

  of SysSleep:
    frame.a0 = syscallSleep(frame.a0)

  of SysGetDateTime:
    frame.a0 = syscallGetDateTime(frame.a0)

  of SysReadFile:
    frame.a0 = syscallReadFile(frame.a0, frame.a1, frame.a2)

  of SysWriteFile:
    frame.a0 = syscallWriteFile(frame.a0, frame.a1, frame.a2)

  of SysOpen:
    frame.a0 = syscallOpen(frame.a0, frame.a1)

  of SysReadFd:
    frame.a0 = syscallReadFd(frame.a0, frame.a1, frame.a2)

  of SysWriteFd:
    frame.a0 = syscallWriteFd(frame.a0, frame.a1, frame.a2)

  of SysClose:
    frame.a0 = syscallClose(frame.a0)

  of SysLseek:
    frame.a0 = syscallLseek(frame.a0, frame.a1, frame.a2)

  of SysPipe:
    frame.a0 = syscallPipe(frame.a0)

  of SysDup2:
    frame.a0 = syscallDup2(frame.a0, frame.a1)

  of SysGetCwd:
    frame.a0 = syscallGetCwd(frame.a0, frame.a1)

  of SysSetCwd:
    frame.a0 = syscallSetCwd(frame.a0)

  of SysGetBitMap:
    frame.a0 = syscallGetBitMap(frame.a0)

  of SysIpcSend:
    frame.a0 = syscallIpcSend(frame.a0, frame.a1)

  of SysIpcReceive:
    frame.a0 = syscallIpcReceive(frame.a0)

  of SysIpcTryReceive:
    frame.a0 = syscallIpcTryReceive(frame.a0)

  of SysIpcSendPacket:
    frame.a0 = syscallIpcSendPacket(frame.a0, frame.a1)

  of SysIpcReceivePacket:
    frame.a0 = syscallIpcReceivePacket(frame.a0)

  of SysIpcTryReceivePacket:
    frame.a0 = syscallIpcTryReceivePacket(frame.a0)

  of SysRawNetInfo:
    frame.a0 = syscallRawNetInfo(frame.a0)

  of SysRawNetInit:
    frame.a0 = syscallRawNetInit()

  of SysRawNetMac:
    frame.a0 = syscallRawNetMac(frame.a0)

  of SysRawNetRecv:
    frame.a0 = syscallRawNetRecv(frame.a0, frame.a1)

  of SysRawNetSend:
    frame.a0 = syscallRawNetSend(frame.a0, frame.a1)

  of SysKill:
    frame.a0 = syscallKill(frame.a0)

  of SysFsServiceRegister:
    frame.a0 = syscallFsServiceRegister()

  of SysFsServiceReceive:
    frame.a0 = syscallFsServiceReceive(frame.a0)

  of SysFsServiceReply:
    frame.a0 = syscallFsServiceReply(frame.a0)

  of SysRawLs:
    frame.a0 = syscallRawLs(frame.a0, frame.a1, frame.a2)

  of SysRawMkdir:
    frame.a0 = syscallRawMkdir(frame.a0)

  of SysRawUnlink:
    frame.a0 = syscallRawUnlink(frame.a0)

  of SysRawRmdir:
    frame.a0 = syscallRawRmdir(frame.a0)

  of SysRawReadFile:
    frame.a0 = syscallRawReadFile(frame.a0, frame.a1, frame.a2)

  of SysRawWriteFile:
    frame.a0 = syscallRawWriteFile(frame.a0, frame.a1, frame.a2)

  of SysBlockServiceRegister:
    frame.a0 = syscallBlockServiceRegister()

  of SysBlockServiceReceive:
    frame.a0 = syscallBlockServiceReceive(frame.a0)

  of SysBlockServiceReply:
    frame.a0 = syscallBlockServiceReply(frame.a0)

  of SysRawBlockRead:
    frame.a0 = syscallRawBlockRead(frame.a0, frame.a1)

  of SysRawBlockWrite:
    frame.a0 = syscallRawBlockWrite(frame.a0, frame.a1)

  of SysServiceManagerRegister:
    frame.a0 = syscallServiceManagerRegister()

  of SysServiceRegister:
    frame.a0 = syscallServiceRegister(frame.a0, frame.a1)

  of SysServiceReady:
    frame.a0 = syscallServiceReady(frame.a0, frame.a1)

  of SysServiceUnregister:
    frame.a0 = syscallServiceUnregister(frame.a0)

  of SysServiceList:
    frame.a0 = syscallServiceList(frame.a0, frame.a1)
  
  of SysGetPid:
    frame.a0 = syscallGetPid()
  
  of SysTraceCtl:
    frame.a0 = syscallTraceCtl(frame.a0, frame.a1)

  of SysEntropy:
    frame.a0 = syscallEntropy(frame.a0, frame.a1)
  
  of SysGetPpid:
    frame.a0 = syscallGetPpid()

  else:
    frame.a0 = U64(-1'i64)
  
  traceSyscallExit(frame)
