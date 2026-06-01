## Provides wrappers for raw network device syscalls.
import ./base
import ../../../lib/syscall_ids


## Invokes the raw net info syscall wrapper.
proc sysRawNetInfo*(info: ptr SysNetDeviceInfo): I32 =
  I32(rawSyscall3(SysRawNetInfo, cast[U64](info), 0, 0))


## Invokes the raw net init syscall wrapper.
proc sysRawNetInit*(): I32 =
  I32(rawSyscall3(SysRawNetInit, 0, 0, 0))


## Invokes the raw net mac syscall wrapper.
proc sysRawNetMac*(mac: pointer): I32 =
  I32(rawSyscall3(SysRawNetMac, cast[U64](mac), 0, 0))


## Invokes the raw net recv syscall wrapper.
proc sysRawNetRecv*(buf: pointer, capacity: U64): I32 =
  I32(rawSyscall3(SysRawNetRecv, cast[U64](buf), capacity, 0))


## Invokes the raw net send syscall wrapper.
proc sysRawNetSend*(buf: pointer, size: U64): I32 =
  I32(rawSyscall3(SysRawNetSend, cast[U64](buf), size, 0))
