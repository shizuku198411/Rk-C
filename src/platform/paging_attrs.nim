## Dispatches page-table memory attributes to the active platform.
import ../lib/types

when defined(platformMilkVDuo256m):
  import ./milkv_duo256m/paging_attrs as attrs
else:
  import ./qemu_virt/paging_attrs as attrs


## Applies active-platform attributes for normal memory mappings.
func normalMemoryFlags*(flags: U64): U64 {.inline.} =
  attrs.normalMemoryFlags(flags)


## Applies active-platform attributes for device memory mappings.
func deviceMemoryFlags*(flags: U64): U64 {.inline.} =
  attrs.deviceMemoryFlags(flags)
