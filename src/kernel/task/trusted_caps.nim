## Defines kernel-trusted capability grants for read-only /bin executables.
import ../../lib/syscall_caps
import ../../lib/types
import ../../lib/fixed_string


const TrustedCapMaxPerPath = 4

type
  TrustedCapPathGrant* = object
    path*: cstring
    capabilityCount*: U32
    capabilities*: array[TrustedCapMaxPerPath, U32]


## Builds a trusted path grant with one capability.
template trustedCapGrant(pathValue: cstring, cap0: U32): TrustedCapPathGrant =
  TrustedCapPathGrant(
    path: pathValue,
    capabilityCount: U32(1),
    capabilities: [cap0, SysCapNone, SysCapNone, SysCapNone],
  )


## Builds a trusted path grant with two capabilities.
template trustedCapGrant(pathValue: cstring, cap0, cap1: U32): TrustedCapPathGrant =
  TrustedCapPathGrant(
    path: pathValue,
    capabilityCount: U32(2),
    capabilities: [cap0, cap1, SysCapNone, SysCapNone],
  )


## Builds a trusted path grant with three capabilities.
template trustedCapGrant(pathValue: cstring, cap0, cap1, cap2: U32): TrustedCapPathGrant =
  TrustedCapPathGrant(
    path: pathValue,
    capabilityCount: U32(3),
    capabilities: [cap0, cap1, cap2, SysCapNone],
  )


const TrustedCapPathGrants*: array[10, TrustedCapPathGrant] = [
  trustedCapGrant(
    cstring"/bin/svcmgtd",
    SysCapServiceManager,
    SysCapProcessList,
    SysCapProcessKill,
  ),
  trustedCapGrant(cstring"/bin/procmgtd", SysCapProcessList, SysCapProcessKill),
  trustedCapGrant(cstring"/bin/procfsd", SysCapProcessList),
  trustedCapGrant(cstring"/bin/fsd", SysCapRawFs),
  trustedCapGrant(cstring"/bin/blockd", SysCapRawBlock),
  trustedCapGrant(cstring"/bin/netd", SysCapRawNet),
  trustedCapGrant(cstring"/bin/stracectl", SysCapTrace),
  trustedCapGrant(cstring"/bin/kill", SysCapProcessKill),
  trustedCapGrant(cstring"/bin/shutdown", SysCapShutdown),
  trustedCapGrant(cstring"/bin/svc", SysCapServiceManager),
]


## Converts a trusted grant capability list into a mask.
proc capabilityMask(grant: TrustedCapPathGrant): U32 =
  var i = U32(0)
  while i < grant.capabilityCount and i < U32(TrustedCapMaxPerPath):
    result = result or grant.capabilities[i]
    inc i


## Returns the kernel-trusted capability mask for an executable path.
proc trustedCapsForPath*(path: cstring): U32 =
  for grant in TrustedCapPathGrants:
    if cstringEq(path, grant.path):
      return capabilityMask(grant)

  SysCapNone
