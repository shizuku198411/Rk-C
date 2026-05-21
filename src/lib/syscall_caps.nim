## Defines syscall capability bits and display names.
import ./types


const
  SysCapNone* = U32(0)
  SysCapServiceManager* = U32(1'u32 shl 0)
  SysCapRawFs* = U32(1'u32 shl 1)
  SysCapRawBlock* = U32(1'u32 shl 2)
  SysCapRawNet* = U32(1'u32 shl 3)
  SysCapProcessList* = U32(1'u32 shl 4)
  SysCapProcessKill* = U32(1'u32 shl 5)
  SysCapTrace* = U32(1'u32 shl 6)
  SysCapShutdown* = U32(1'u32 shl 7)

  SysCapAllKnown* = SysCapServiceManager or SysCapRawFs or SysCapRawBlock or
    SysCapRawNet or SysCapProcessList or SysCapProcessKill or SysCapTrace or
    SysCapShutdown

  SysCapServiceManagerName* = "sys_service_manager"
  SysCapRawFsName* = "sys_raw_fs"
  SysCapRawBlockName* = "sys_raw_block"
  SysCapRawNetName* = "sys_raw_net"
  SysCapProcessListName* = "sys_process_list"
  SysCapProcessKillName* = "sys_process_kill"
  SysCapTraceName* = "sys_trace_ctl"
  SysCapShutdownName* = "sys_shutdown"
