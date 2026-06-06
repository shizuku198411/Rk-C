## Provides shared userspace names for syscall capability masks.
import ../../../lib/syscall_caps
import ../../../lib/types


type
  UserCapabilityNameEntry* = object
    bit*: U32
    name*: cstring


const UserCapabilityNameEntries*: array[8, UserCapabilityNameEntry] = [
  UserCapabilityNameEntry(
    bit: SysCapServiceManager,
    name: cstring(SysCapServiceManagerName),
  ),
  UserCapabilityNameEntry(
    bit: SysCapRawFs,
    name: cstring(SysCapRawFsName),
  ),
  UserCapabilityNameEntry(
    bit: SysCapRawBlock,
    name: cstring(SysCapRawBlockName),
  ),
  UserCapabilityNameEntry(
    bit: SysCapRawNet,
    name: cstring(SysCapRawNetName),
  ),
  UserCapabilityNameEntry(
    bit: SysCapProcessList,
    name: cstring(SysCapProcessListName),
  ),
  UserCapabilityNameEntry(
    bit: SysCapProcessKill,
    name: cstring(SysCapProcessKillName),
  ),
  UserCapabilityNameEntry(
    bit: SysCapTrace,
    name: cstring(SysCapTraceName),
  ),
  UserCapabilityNameEntry(
    bit: SysCapShutdown,
    name: cstring(SysCapShutdownName),
  ),
]


## Returns whether the capability mask contains no capability bits.
proc capMaskIsNone*(mask: U32): bool =
  mask == SysCapNone


## Returns unknown capability bits not represented by the shared capability table.
proc unknownCapabilityMask*(mask: U32): U32 =
  mask and (not SysCapAllKnown)
