import syscall_types
import types


type
  SysServiceSpec* = object
    kind*: U32
    name*: cstring
    path*: cstring
    required*: bool


const
  SysManagedServiceCount* = 4


let managedServices*: array[SysManagedServiceCount, SysServiceSpec] = [
  SysServiceSpec(kind: SysServiceKindProcess, name: "procmgtd", path: "/bin/procmgtd", required: true),
  SysServiceSpec(kind: SysServiceKindBlock, name: "blockd", path: "/bin/blockd", required: true),
  SysServiceSpec(kind: SysServiceKindFs, name: "fsd", path: "/bin/fsd", required: true),
  SysServiceSpec(kind: SysServiceKindNet, name: "netd", path: "/bin/netd", required: false),
]


proc serviceKindKnown*(kind: U32): bool =
  kind == SysServiceKindManager or kind == SysServiceKindBlock or
    kind == SysServiceKindFs or kind == SysServiceKindProcess or
    kind == SysServiceKindNet


proc serviceNameByKind*(kind: U32): cstring =
  if kind == SysServiceKindManager:
    return "svcmgtd"

  var i = 0
  while i < managedServices.len:
    if managedServices[i].kind == kind:
      return managedServices[i].name
    inc i

  "unknown"


proc servicePathByKind*(kind: U32): cstring =
  var i = 0
  while i < managedServices.len:
    if managedServices[i].kind == kind:
      return managedServices[i].path
    inc i

  nil


proc serviceRequiredByKind*(kind: U32): bool =
  if kind == SysServiceKindManager:
    return true

  var i = 0
  while i < managedServices.len:
    if managedServices[i].kind == kind:
      return managedServices[i].required
    inc i

  false
