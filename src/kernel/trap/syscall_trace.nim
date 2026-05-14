import ../../lib/types
import ../../lib/syscall_ids
import ../dev/console
import ../task/process
import ../trap/trap_types
import ../mm/usercopy


const
  traceStrBufSize = 64

var
  syscallTraceEnabled* = false
  syscallTracePid*: int32 = -1
  traceStrBuf: array[traceStrBufSize, char]

proc syscallName*(num: U64): cstring = 
  case num:
  of SysWrite: cstring("write")
  of SysRead: cstring("read")
  of SysPs: cstring("ps")
  of SysTicks: cstring("ticks")
  of SysExit: cstring("exit")
  of SysLs: cstring("ls")
  of SysTraps: cstring("traps")
  of SysMkdir: cstring("mkdir")
  of SysExec: cstring("exec")
  of SysWait: cstring("wait")
  of SysUnlink: cstring("unlink")
  of SysRmdir: cstring("rmdir")
  of SysShutdown: cstring("shutdown")
  of SysGetDateTime: cstring("get_date_time")
  of SysReadFile: cstring("read_file")
  of SysWriteFile: cstring("write_file")
  of SysGetCwd: cstring("get_cwd")
  of SysSetCwd: cstring("set_cwd")
  of SysGetBitMap: cstring("get_bit_map")
  of SysIpcSend: cstring("ipc_send")
  of SysIpcReceive: cstring("ipc_receive")
  of SysKill: cstring("kill")
  of SysFsServiceRegister: cstring("fs_service_register")
  of SysFsServiceReceive: cstring("fs_service_receive")
  of SysFsServiceReply: cstring("fs_service_reply")
  of SysRawLs: cstring("raw_ls")
  of SysRawMkdir: cstring("raw_mkdir")
  of SysRawUnlink: cstring("raw_unlink")
  of SysRawRmdir: cstring("raw_rmdir")
  of SysRawReadFile: cstring("raw_read_file")
  of SysRawWriteFile: cstring("raw_write_file")
  of SysBlockServiceRegister: cstring("block_service_register")
  of SysBlockServiceReceive: cstring("block_service_receive")
  of SysBlockServiceReply: cstring("block_service_reply")
  of SysRawBlockRead: cstring("raw_block_read")
  of SysRawBlockWrite: cstring("raw_block_write")
  of SysServiceManagerRegister: cstring("service_manager_register")
  of SysServiceRegister: cstring("service_register")
  of SysServiceUnregister: cstring("service_unregister")
  of SysYield: cstring("yield")
  of SysSleep: cstring("sleep")
  of SysGetPid: cstring("get_pid")
  of SysServiceList: cstring("service_list")
  of SysIpcTryReceive: cstring("ipc_try_receive")
  of SysIpcSendPacket: cstring("ipc_send_packet")
  of SysIpcReceivePacket: cstring("ipc_receive_packet")
  of SysIpcTryReceivePacket: cstring("ipc_try_receive_packet")
  of SysRawNetInfo: cstring("raw_net_info")
  of SysRawNetInit: cstring("raw_net_init")
  of SysRawNetMac: cstring("raw_net_mac")
  of SysRawNetRecv: cstring("raw_net_recv")
  of SysRawNetSend: cstring("raw_net_send")
  of SysTraceCtl: cstring("trace_ctl")
  of SysEntropy: cstring("entropy")
  else: cstring("unknown")


proc shouldTrace(): bool =
  if not syscallTraceEnabled:
    return false
  if currentProc == nil:
    return false
  if syscallTracePid >= 0 and currentProc.pid != syscallTracePid:
    return false
  true


proc printUserCStringArg(ptrVal: U64) =
  if ptrVal == 0:
    print("null")
    return

  if copyUserCString(addr traceStrBuf[0], ptrVal, U64(traceStrBufSize)) < 0:
    print("<badptr>")
    return

  print("\"")
  print(cast[cstring](addr traceStrBuf[0]))
  print("\"")


proc traceSyscallEnter*(frame: ptr TrapFrame) =
  if not shouldTrace():
    return

  print("[strace] pid = ")
  printSigned(currentProc.pid)
  print(" ")
  print(syscallName(frame.a3))
  print("(")

  case frame.a3:
  of SysRawReadFile, SysRawWriteFile:
    printUserCStringArg(frame.a0)
  else:
    printPtr(frame.a0)
  
  print(", ")
  printPtr(frame.a1)
  print(", ")
  printPtr(frame.a2)

  print(")")


proc traceSyscallExit*(frame: ptr TrapFrame) =
  if not shouldTrace():
    return

  print(" = ")
  printPtr(frame.a0)
  putChar('\n')
