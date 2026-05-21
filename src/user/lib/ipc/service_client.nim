## Provides userland service lookup helpers.
import ../core/syscall

const
  ServiceClientCap = 8

var serviceInfos: array[ServiceClientCap, SysServiceInfo]


## Handles service catalog data for pid by kind.
proc servicePidByKind*(kind: U32): I32 =
  let count = sysServiceList(addr serviceInfos[0], U64(ServiceClientCap))
  if count < 0:
    return -1

  var i = I32(0)
  while i < count:
    if serviceInfos[i].kind == kind and serviceInfos[i].available != 0:
      return serviceInfos[i].pid
    inc i

  -1


## Looks up registered service pid by kind.
proc registeredServicePidByKind*(kind: U32): I32 =
  let count = sysServiceList(addr serviceInfos[0], U64(ServiceClientCap))
  if count < 0:
    return -1

  var i = I32(0)
  while i < count:
    if serviceInfos[i].kind == kind and serviceInfos[i].registered != 0:
      return serviceInfos[i].pid
    inc i
  
  -1