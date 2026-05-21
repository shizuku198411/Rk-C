## Formats syscall trace output for debugging user processes.
import ../../lib/types
import ../../lib/syscall_ids
import ../dev/console
import ../task/process
import ../trap/trap_types
import ../mm/usercopy


const
  traceStrBufSize = 64
  tracePreviewBufSize = 48

var
  syscallTraceEnabled* = false
  syscallTraceVerbose* = false
  syscallTracePid*: int32 = -1
  traceStrBuf: array[traceStrBufSize, char]
  tracePreviewBuf: array[tracePreviewBufSize, U8]

## Handles the name syscall operation.
proc syscallName*(num: U64): cstring = 
  case num:
  of SysWrite: cstring("write")
  of SysRead: cstring("read")
  of SysPs: cstring("ps")
  of SysTicks: cstring("ticks")
  of SysCpuInfo: cstring("cpu_info")
  of SysKmsg: cstring("kmsg")
  of SysPoll: cstring("poll")
  of SysExit: cstring("exit")
  of SysLs: cstring("ls")
  of SysTraps: cstring("traps")
  of SysMkdir: cstring("mkdir")
  of SysExec: cstring("exec")
  of SysExecAs: cstring("exec_as")
  of SysWait: cstring("wait")
  of SysUnlink: cstring("unlink")
  of SysRmdir: cstring("rmdir")
  of SysShutdown: cstring("shutdown")
  of SysGetDateTime: cstring("get_date_time")
  of SysReadFile: cstring("read_file")
  of SysWriteFile: cstring("write_file")
  of SysFsInfo: cstring("fs_info")
  of SysRename: cstring("rename")
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
  of SysRawFileSize: cstring("raw_file_size")
  of SysRawReadRange: cstring("raw_read_range")
  of SysRawRename: cstring("raw_rename")
  of SysRawChmod: cstring("raw_chmod")
  of SysRawChown: cstring("raw_chown")
  of SysBlockServiceRegister: cstring("block_service_register")
  of SysBlockServiceReceive: cstring("block_service_receive")
  of SysBlockServiceReply: cstring("block_service_reply")
  of SysRawBlockRead: cstring("raw_block_read")
  of SysRawBlockWrite: cstring("raw_block_write")
  of SysServiceManagerRegister: cstring("service_manager_register")
  of SysServiceRegister: cstring("service_register")
  of SysServiceReady: cstring("service_ready")
  of SysServiceUnregister: cstring("service_unregister")
  of SysYield: cstring("yield")
  of SysSleep: cstring("sleep")
  of SysGetPid: cstring("get_pid")
  of SysGetUid: cstring("get_uid")
  of SysGetGid: cstring("get_gid")
  of SysSetUser: cstring("set_user")
  of SysChmod: cstring("chmod")
  of SysChown: cstring("chown")
  of SysLastError: cstring("last_error")
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
  of SysOpen: cstring("open")
  of SysReadFd: cstring("read_fd")
  of SysWriteFd: cstring("write_fd")
  of SysClose: cstring("close")
  of SysLseek: cstring("lseek")
  of SysPipe: cstring("pipe")
  of SysDup2: cstring("dup2")
  of SysSignalPoll: cstring("signal_poll")
  else: cstring("unknown")


## Implements the should trace kernel helper.
proc shouldTrace(): bool =
  if not syscallTraceEnabled:
    return false
  if currentProc == nil:
    return false
  if syscallTracePid >= 0 and currentProc.pid != syscallTracePid:
    return false
  true


## Prints user cstring arg.
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


## Prints escaped byte.
proc printEscapedByte(ch: U8) =
  case ch
  of U8('\n'):
    print("\\n")
  of U8('\r'):
    print("\\r")
  of U8('\t'):
    print("\\t")
  of U8('"'):
    print("\\\"")
  of U8('\\'):
    print("\\\\")
  else:
    if ch >= U8(32) and ch < U8(127):
      putChar(char(ch))
    else:
      print(".")


## Prints buffer preview.
proc printBufferPreview(ptrVal, len: U64) =
  if not syscallTraceVerbose:
    return
  if ptrVal == 0 or len == 0:
    return

  var previewLen = len
  if previewLen > U64(tracePreviewBufSize):
    previewLen = U64(tracePreviewBufSize)

  print(", preview=\"")
  if copyFromUser(addr tracePreviewBuf[0], ptrVal, previewLen) != 0:
    print("<badptr>")
  else:
    var i = U64(0)
    while i < previewLen:
      printEscapedByte(tracePreviewBuf[i])
      inc i
    if len > previewLen:
      print("...")
  print("\"")


## Prints name.
proc printName(name: cstring) =
  print(name)
  print("=")


## Prints named ptr.
proc printNamedPtr(name: cstring, value: U64) =
  printName(name)
  printPtr(value)


## Prints named u64.
proc printNamedU64(name: cstring, value: U64) =
  printName(name)
  printUnsigned(value)


## Prints named i64.
proc printNamedI64(name: cstring, value: U64) =
  printName(name)
  printSigned(int64(value))


## Prints named cstring.
proc printNamedCString(name: cstring, value: U64) =
  printName(name)
  printUserCStringArg(value)


## Prints named bool.
proc printNamedBool(name: cstring, value: U64) =
  printName(name)
  if value == 0:
    print("false")
  else:
    print("true")


## Prints trace ctl cmd.
proc printTraceCtlCmd(value: U64) =
  case value
  of 0:
    print("off")
  of 1:
    print("on")
  of 2:
    print("pid")
  of 3:
    print("verbose")
  else:
    printUnsigned(value)


## Prints named trace ctl cmd.
proc printNamedTraceCtlCmd(name: cstring, value: U64) =
  printName(name)
  printTraceCtlCmd(value)


## Prints default args.
proc printDefaultArgs(frame: ptr TrapFrame) =
  printNamedPtr("a0", frame.a0)
  print(", ")
  printNamedPtr("a1", frame.a1)
  print(", ")
  printNamedPtr("a2", frame.a2)


## Prints syscall args.
proc printSyscallArgs(frame: ptr TrapFrame) =
  case frame.a3
  of SysWrite:
    printNamedPtr("buf", frame.a0)
    print(", ")
    printNamedU64("len", frame.a1)
    printBufferPreview(frame.a0, frame.a1)
  of SysRead:
    printNamedPtr("buf", frame.a0)
    print(", ")
    printNamedU64("len", frame.a1)
  of SysExit:
    printNamedU64("status", frame.a0)
  of SysLs, SysMkdir, SysUnlink, SysRmdir, SysSetCwd:
    printNamedCString("path", frame.a0)
  of SysRename:
    printNamedCString("old", frame.a0)
    print(", ")
    printNamedCString("new", frame.a1)
  of SysReadFile:
    printNamedCString("path", frame.a0)
    print(", ")
    printNamedPtr("buf", frame.a1)
    print(", ")
    printNamedU64("capacity", frame.a2)
  of SysWriteFile:
    printNamedCString("path", frame.a0)
    print(", ")
    printNamedPtr("buf", frame.a1)
    print(", ")
    printNamedU64("size", frame.a2)
  of SysOpen:
    printNamedCString("path", frame.a0)
    print(", ")
    printNamedU64("flags", frame.a1)
  of SysReadFd:
    printNamedI64("fd", frame.a0)
    print(", ")
    printNamedPtr("buf", frame.a1)
    print(", ")
    printNamedU64("len", frame.a2)
  of SysWriteFd:
    printNamedI64("fd", frame.a0)
    print(", ")
    printNamedPtr("buf", frame.a1)
    print(", ")
    printNamedU64("len", frame.a2)
    printBufferPreview(frame.a1, frame.a2)
  of SysClose:
    printNamedI64("fd", frame.a0)
  of SysLseek:
    printNamedI64("fd", frame.a0)
    print(", ")
    printNamedI64("offset", frame.a1)
    print(", ")
    printNamedU64("whence", frame.a2)
  of SysPipe:
    printNamedPtr("fds", frame.a0)
  of SysDup2:
    printNamedI64("oldfd", frame.a0)
    print(", ")
    printNamedI64("newfd", frame.a1)
  of SysPoll:
    printNamedPtr("events", frame.a0)
    print(", ")
    printNamedU64("count", frame.a1)
    print(", ")
    printNamedU64("timeout_ticks", frame.a2)
  of SysExec:
    printNamedCString("path", frame.a0)
    print(", ")
    printNamedCString("arg", frame.a1)
    print(", ")
    printNamedBool("detached", frame.a2)
  of SysExecAs:
    printNamedCString("path", frame.a0)
    print(", ")
    printNamedCString("arg", frame.a1)
    print(", ")
    printNamedU64("uid_gid", frame.a2)
  of SysWait, SysKill:
    printNamedI64("pid", frame.a0)
  of SysGetCwd:
    printNamedPtr("buf", frame.a0)
    print(", ")
    printNamedU64("capacity", frame.a1)
  of SysPs:
    printNamedPtr("entries", frame.a0)
    print(", ")
    printNamedU64("max", frame.a1)
    print(", ")
    printNamedU64("flags", frame.a2)
  of SysTraps:
    printNamedPtr("out", frame.a0)
  of SysGetBitMap:
    printNamedPtr("info", frame.a0)
  of SysFsInfo:
    printNamedPtr("entries", frame.a0)
    print(", ")
    printNamedU64("max", frame.a1)
  of SysIpcSend:
    printNamedI64("pid", frame.a0)
    print(", ")
    printNamedCString("msg", frame.a1)
  of SysIpcReceive, SysIpcTryReceive:
    printNamedPtr("msg", frame.a0)
  of SysIpcSendPacket:
    printNamedI64("pid", frame.a0)
    print(", ")
    printNamedPtr("packet", frame.a1)
  of SysIpcReceivePacket, SysIpcTryReceivePacket:
    printNamedPtr("packet", frame.a0)
  of SysFsServiceReceive:
    printNamedPtr("req", frame.a0)
  of SysFsServiceReply:
    printNamedPtr("resp", frame.a0)
  of SysRawLs:
    printNamedCString("path", frame.a0)
    print(", ")
    printNamedPtr("entries", frame.a1)
    print(", ")
    printNamedU64("max", frame.a2)
  of SysRawRename:
    printNamedCString("old", frame.a0)
    print(", ")
    printNamedCString("new", frame.a1)
  of SysRawChmod:
    printNamedCString("path", frame.a0)
    print(", ")
    printNamedU64("mode", frame.a1)
  of SysChmod:
    printNamedCString("path", frame.a0)
    print(", ")
    printNamedU64("mode", frame.a1)
  of SysRawChown:
    printNamedCString("path", frame.a0)
    print(", ")
    printNamedU64("uid_gid", frame.a1)
  of SysChown:
    printNamedCString("path", frame.a0)
    print(", ")
    printNamedU64("uid_gid", frame.a1)
  of SysRawMkdir, SysRawUnlink, SysRawRmdir, SysRawReadFile, SysRawWriteFile,
      SysRawFileSize:
    printNamedCString("path", frame.a0)
    print(", ")
    printNamedPtr("arg1", frame.a1)
    print(", ")
    printNamedU64("arg2", frame.a2)
  of SysRawReadRange:
    printNamedPtr("req", frame.a0)
  of SysBlockServiceReceive:
    printNamedPtr("req", frame.a0)
  of SysBlockServiceReply:
    printNamedPtr("resp", frame.a0)
  of SysRawBlockRead:
    printNamedU64("block", frame.a0)
    print(", ")
    printNamedPtr("out", frame.a1)
  of SysRawBlockWrite:
    printNamedU64("block", frame.a0)
    print(", ")
    printNamedPtr("in", frame.a1)
  of SysServiceRegister:
    printNamedU64("kind", frame.a0)
    print(", ")
    printNamedI64("pid", frame.a1)
  of SysServiceUnregister:
    printNamedU64("kind", frame.a0)
  of SysSetUser:
    printNamedU64("uid", frame.a0)
    print(", ")
    printNamedU64("gid", frame.a1)
  of SysServiceList:
    printNamedPtr("entries", frame.a0)
    print(", ")
    printNamedU64("max", frame.a1)
  of SysSleep:
    printNamedU64("ticks", frame.a0)
  of SysCpuInfo:
    printNamedPtr("info", frame.a0)
  of SysKmsg:
    printNamedPtr("buf", frame.a0)
    print(", ")
    printNamedU64("capacity", frame.a1)
  of SysRawNetMac:
    printNamedPtr("mac", frame.a0)
  of SysRawNetRecv:
    printNamedPtr("buf", frame.a0)
    print(", ")
    printNamedU64("capacity", frame.a1)
  of SysRawNetSend:
    printNamedPtr("buf", frame.a0)
    print(", ")
    printNamedU64("size", frame.a1)
  of SysTraceCtl:
    printNamedTraceCtlCmd("cmd", frame.a0)
    print(", ")
    printNamedU64("value", frame.a1)
  of SysEntropy:
    printNamedPtr("buf", frame.a0)
    print(", ")
    printNamedU64("size", frame.a1)
  else:
    printDefaultArgs(frame)


## Implements the trace syscall enter kernel helper.
proc traceSyscallEnter*(frame: ptr TrapFrame) =
  if not shouldTrace():
    return

  print("[strace] -> pid=")
  printSigned(currentProc.pid)
  print(" exe=")
  print(currentProc.exePath)
  print(" sys=")
  print(syscallName(frame.a3))
  print("#")
  printUnsigned(frame.a3)
  print("(")

  printSyscallArgs(frame)
  print(")")
  putChar('\n')


## Implements the trace syscall exit kernel helper.
proc traceSyscallExit*(frame: ptr TrapFrame) =
  if not shouldTrace():
    return

  print("[strace] <- pid=")
  printSigned(currentProc.pid)
  print(" sys=")
  print(syscallName(frame.a3))
  print("#")
  printUnsigned(frame.a3)
  print(" ret=")
  printPtr(frame.a0)
  putChar('\n')
