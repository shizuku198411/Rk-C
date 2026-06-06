## Provides wrappers for console I/O and system-level syscalls.
import ./base
import ../../../lib/syscall_ids


## Invokes the write syscall wrapper.
proc sysWrite*(buf: pointer, len: U64): U64 =
  rawSyscall3(SysWrite, cast[U64](buf), len, 0)


## Invokes the read syscall wrapper.
proc sysRead*(buf: pointer, len: U64): U64 =
  rawSyscall3(SysRead, cast[U64](buf), len, 0)


## Invokes the ticks syscall wrapper.
proc sysTicks*(): U64 =
  rawSyscall3(SysTicks, 0, 0, 0)


## Invokes the cpu info syscall wrapper.
proc sysCpuInfo*(info: ptr SysCpuInfo): I32 =
  I32(rawSyscall3(SysCpuInfo, cast[U64](info), 0, 0))


## Invokes the cpu static info syscall wrapper.
proc sysCpuStaticInfo*(info: ptr SysCpuStaticInfo): I32 =
  I32(rawSyscall3(SysCpuStaticInfo, cast[U64](info), 0, 0))


## Invokes the console info syscall wrapper.
proc sysConsoleInfo*(info: ptr SysConsoleInfo): I32 =
  I32(rawSyscall3(SysConsoleInfo, cast[U64](info), 0, 0))


## Invokes the kmsg syscall wrapper.
proc sysKmsg*(buf: pointer, capacity: U64): I32 =
  I32(rawSyscall3(SysKmsg, cast[U64](buf), capacity, 0))


## Invokes the traps syscall wrapper.
proc sysTraps*(entries: ptr SysTrapCount): U64 =
  rawSyscall3(SysTraps, cast[U64](entries), 0, 0)


## Invokes the exit syscall wrapper.
proc sysExit*(status: U64) {.noreturn.} =
  discard rawSyscall3(SysExit, status, 0, 0)
  halt()


## Invokes the shutdown syscall wrapper.
proc sysShutdown*(): I32 =
  I32(rawSyscall3(SysShutdown, 0, 0, 0))


## Invokes the get date time syscall wrapper.
proc sysGetDateTime*(dt: ptr SysDateTime): I32 =
  I32(rawSyscall3(SysGetDateTime, cast[U64](dt), 0, 0))


## Invokes the poll syscall wrapper.
proc sysPoll*(events: ptr SysPollEvent, count: U64, timeoutTicks: U64): I32 =
  I32(rawSyscall3(SysPoll, cast[U64](events), count, timeoutTicks))


## Invokes the signal poll syscall wrapper.
proc sysSignalPoll*(signal: ptr U32): I32 =
  I32(rawSyscall3(SysSignalPoll, cast[U64](signal), 0, 0))


## Invokes the yield syscall wrapper.
proc sysYield*(): I32 =
  I32(rawSyscall3(SysYield, 0, 0, 0))


## Invokes the sleep syscall wrapper.
proc sysSleep*(ticks: U64): I32 =
  I32(rawSyscall3(SysSleep, ticks, 0, 0))


## Invokes the last error syscall wrapper.
proc sysLastError*(): I32 =
  I32(rawSyscall3(SysLastError, 0, 0, 0))


## Invokes the entropy syscall wrapper.
proc sysEntropy*(buf: pointer, size: U64): I32 =
  I32(rawSyscall3(SysEntropy, cast[U64](buf), size, 0))


## Invokes the get cap syscall wrapper.
proc sysGetCap*(buf: pointer, size: U64): I32 =
  I32(rawSyscall3(SysGetCap, cast[U64](buf), size, 0))
