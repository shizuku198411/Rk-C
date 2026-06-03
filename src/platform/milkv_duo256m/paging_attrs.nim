## Provides C906/T-Head page-table memory attribute helpers for Milk-V Duo 256M.
import ../../lib/types

const
  PteTheadSecure = U64(1) shl 59
  PteTheadShare = U64(1) shl 60
  PteTheadBuffer = U64(1) shl 61
  PteTheadCache = U64(1) shl 62
  PteTheadStrongOrder = U64(1) shl 63
  PteTheadMemoryTypeMask =
    PteTheadSecure or PteTheadShare or PteTheadBuffer or
    PteTheadCache or PteTheadStrongOrder
  PteTheadNormalMemory = PteTheadShare or PteTheadBuffer or PteTheadCache
  PteTheadDeviceMemory = PteTheadStrongOrder or PteTheadShare


## Applies C906 cacheable/shareable attributes for normal memory mappings.
func normalMemoryFlags*(flags: U64): U64 {.inline.} =
  if (flags and PteTheadMemoryTypeMask) != U64(0):
    flags
  else:
    flags or PteTheadNormalMemory


## Applies C906 strongly ordered attributes for device memory mappings.
func deviceMemoryFlags*(flags: U64): U64 {.inline.} =
  (flags and not PteTheadMemoryTypeMask) or PteTheadDeviceMemory
