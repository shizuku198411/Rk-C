import ../../lib/syscall_ids
import ../dev/console
import ../syscall/fs/file_ops
import ../syscall/io/console_io
import ../syscall/ipc/ipc_ops
import ../syscall/mm/memory_ops
import ../syscall/system/system_ops
import ../syscall/task/process_ops
import ../trap/trap_types


proc handleSyscall*(frame: ptr TrapFrame) =
  case frame.a3
  of SysWrite:
    frame.a0 = syscallWrite(frame.a0, frame.a1)

  of SysRead:
    frame.a0 = syscallRead(frame.a0, frame.a1)

  of SysPs:
    frame.a0 = syscallPs(frame.a0, frame.a1)

  of SysTicks:
    frame.a0 = syscallTicks()

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
    syscallShutdown()

  of SysGetDateTime:
    frame.a0 = syscallGetDateTime(frame.a0)

  of SysReadFile:
    frame.a0 = syscallReadFile(frame.a0, frame.a1, frame.a2)

  of SysWriteFile:
    frame.a0 = syscallWriteFile(frame.a0, frame.a1, frame.a2)

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

  of SysKill:
    frame.a0 = syscallKill(frame.a0)

  else:
    print("PANIC: unknown syscall ")
    printUnsigned(frame.a3)
    putChar('\n')
    while true:
      discard
