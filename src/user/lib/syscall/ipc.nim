## Provides wrappers for IPC message and packet syscalls.
import ./base
import ../../../lib/syscall_ids


## Invokes the ipc send syscall wrapper.
proc sysIpcSend*(pid: I32, msg: cstring): I32 =
  I32(rawSyscall3(SysIpcSend, U64(pid), cast[U64](msg), 0))


## Invokes the ipc receive syscall wrapper.
proc sysIpcReceive*(msg: ptr SysIpcMessage): I32 =
  I32(rawSyscall3(SysIpcReceive, cast[U64](msg), 0, 0))


## Invokes the ipc try receive syscall wrapper.
proc sysIpcTryReceive*(msg: ptr SysIpcMessage): I32 =
  I32(rawSyscall3(SysIpcTryReceive, cast[U64](msg), 0, 0))


## Invokes the ipc send packet syscall wrapper.
proc sysIpcSendPacket*(pid: I32, packet: ptr SysIpcPacket): I32 =
  I32(rawSyscall3(SysIpcSendPacket, U64(pid), cast[U64](packet), 0))


## Invokes the ipc receive packet syscall wrapper.
proc sysIpcReceivePacket*(packet: ptr SysIpcPacket): I32 =
  I32(rawSyscall3(SysIpcReceivePacket, cast[U64](packet), 0, 0))


## Invokes the ipc try receive packet syscall wrapper.
proc sysIpcTryReceivePacket*(packet: ptr SysIpcPacket): I32 =
  I32(rawSyscall3(SysIpcTryReceivePacket, cast[U64](packet), 0, 0))
