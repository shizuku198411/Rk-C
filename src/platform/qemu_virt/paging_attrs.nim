## Provides QEMU virt page-table memory attribute helpers.
import ../../lib/types


## Applies platform attributes for normal memory mappings.
func normalMemoryFlags*(flags: U64): U64 {.inline.} =
  flags


## Applies platform attributes for device memory mappings.
func deviceMemoryFlags*(flags: U64): U64 {.inline.} =
  flags
