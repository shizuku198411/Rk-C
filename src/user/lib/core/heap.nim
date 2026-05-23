## Provides a minimal bump allocator on top of brk/sbrk.
import ../../../lib/types
from ./syscall import sysBrk, sysSbrk

var
  heapBase: types.U64 = 0
  heapInitialized = false


proc ensureHeapBase*(): bool =
  if heapInitialized:
    return true

  let current = sysSbrk(0)
  if current < 0:
    return false

  heapBase = types.U64(current)
  heapInitialized = true
  true


proc userAlloc*(size: types.U64): pointer =
  if size == 0:
    return nil

  if size > types.U64(high(types.I64)) - types.U64(7):
    return nil

  if not ensureHeapBase():
    return nil

  let aligned = alignUp(size, types.U64(8))
  if aligned == 0 or aligned > types.U64(high(types.I64)):
    return nil

  let old = sysSbrk(types.I64(aligned))
  if old < 0:
    return nil

  cast[pointer](types.U64(old))


proc userResetHeap*(): bool =
  if not ensureHeapBase():
    return false

  sysBrk(heapBase) == 0
