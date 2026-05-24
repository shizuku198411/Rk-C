## Provides the Nim ORC operating-system allocation bridge for userland apps.
##
## This backend obtains storage from the Rk-C process heap through sbrk, reuses
## released blocks, and lowers brk when released storage reaches the heap tail.
import ../../../lib/types
from ../core/syscall import sysBrk, sysExit, sysSbrk, sysWriteFd


type
  HeapBlock = object
    previous: ptr HeapBlock
    next: ptr HeapBlock
    size: U64
    magic: U64
    state: U64


const
  AllocAlignment = U64(16)
  BlockMagic = U64(0x524b434f5243424c)
  BlockFree = U64(0)
  BlockUsed = U64(1)
  HeaderSize = alignUp(U64(sizeof(HeapBlock)), AllocAlignment)
  MinimumSplitSize = AllocAlignment


var runtimeStderr {.exportc: "stderr".}: pointer = nil
var heapHead: ptr HeapBlock = nil
var heapTail: ptr HeapBlock = nil


## Converts an allocator block into the raw allocation pointer returned to Nim.
proc payloadOf(chunk: ptr HeapBlock): pointer {.inline.} =
  cast[pointer](U64(cast[uint](chunk)) + HeaderSize)


## Locates the allocator block metadata immediately before a returned pointer.
proc blockOf(payload: pointer): ptr HeapBlock {.inline.} =
  cast[ptr HeapBlock](U64(cast[uint](payload)) - HeaderSize)


## Rounds an allocation size safely to the allocator's natural alignment.
proc alignedSize(size: CSize, aligned: var U64): bool =
  let raw = U64(size)
  if raw == U64(0) or raw > U64(high(I64)) or
      raw > high(U64) - (AllocAlignment - U64(1)):
    return false

  aligned = alignUp(raw, AllocAlignment)
  aligned <= U64(high(I64)) - HeaderSize


## Finds a released block large enough for the requested payload.
proc findReusableBlock(size: U64): ptr HeapBlock =
  var chunk = heapHead

  while chunk != nil:
    if chunk.magic == BlockMagic and chunk.state == BlockFree and chunk.size >= size:
      return chunk
    chunk = chunk.next

  nil


## Splits an oversized free block while preserving an aligned reusable remainder.
proc splitBlock(chunk: ptr HeapBlock, size: U64) =
  if chunk.size < size + HeaderSize + MinimumSplitSize:
    return

  let remainder = cast[ptr HeapBlock](U64(cast[uint](payloadOf(chunk))) + size)
  remainder.previous = chunk
  remainder.next = chunk.next
  remainder.size = chunk.size - size - HeaderSize
  remainder.magic = BlockMagic
  remainder.state = BlockFree

  if remainder.next != nil:
    remainder.next.previous = remainder
  else:
    heapTail = remainder

  chunk.next = remainder
  chunk.size = size


## Grows the process break to append one allocator block.
proc appendBlock(size: U64): ptr HeapBlock =
  let total = HeaderSize + size
  let previousBreak = sysSbrk(I64(total))
  if previousBreak < 0:
    return nil

  let chunk = cast[ptr HeapBlock](U64(previousBreak))
  chunk.previous = heapTail
  chunk.next = nil
  chunk.size = size
  chunk.magic = BlockMagic
  chunk.state = BlockUsed

  if heapTail != nil:
    heapTail.next = chunk
  else:
    heapHead = chunk
  heapTail = chunk

  chunk


## Merges a free block with its following free neighbor.
proc mergeFollowing(chunk: ptr HeapBlock) =
  let following = chunk.next
  if following == nil or following.magic != BlockMagic or following.state != BlockFree:
    return

  chunk.size += HeaderSize + following.size
  chunk.next = following.next
  following.magic = U64(0)

  if chunk.next != nil:
    chunk.next.previous = chunk
  else:
    heapTail = chunk


## Returns a trailing free block to the kernel process heap when possible.
proc releaseTrailingBlock(chunk: ptr HeapBlock) =
  if chunk == nil or chunk != heapTail or chunk.state != BlockFree:
    return

  let previous = chunk.previous
  let newBreak = U64(cast[uint](chunk))
  if sysBrk(newBreak) != 0:
    return

  if previous != nil:
    previous.next = nil
  else:
    heapHead = nil
  heapTail = previous


## Allocates raw storage for Nim's standalone osalloc layer from the user heap.
proc malloc*(size: CSize): pointer {.exportc: "malloc", cdecl.} =
  var required = U64(0)
  if not alignedSize(size, required):
    return nil

  var chunk = findReusableBlock(required)
  if chunk != nil:
    splitBlock(chunk, required)
    chunk.state = BlockUsed
    return payloadOf(chunk)

  chunk = appendBlock(required)
  if chunk == nil:
    return nil

  payloadOf(chunk)


## Releases raw storage, coalescing it and returning trailing heap space to brk.
proc free*(p: pointer) {.exportc: "free", cdecl.} =
  if p == nil:
    return

  var chunk = blockOf(p)
  if chunk.magic != BlockMagic or chunk.state != BlockUsed:
    return

  chunk.state = BlockFree
  mergeFollowing(chunk)

  if chunk.previous != nil and chunk.previous.magic == BlockMagic and
      chunk.previous.state == BlockFree:
    chunk = chunk.previous
    mergeFollowing(chunk)

  releaseTrailingBlock(chunk)


## Routes Nim runtime emergency diagnostics to the standard error descriptor.
proc fwrite*(buffer: pointer, size, count: CSize, stream: pointer): CSize {.exportc: "fwrite", cdecl.} =
  discard stream

  if size == CSize(0) or count == CSize(0):
    return CSize(0)
  if U64(count) > high(U64) div U64(size):
    return CSize(0)

  let length = U64(size) * U64(count)
  let written = sysWriteFd(I32(2), buffer, length)
  if written < 0 or U64(written) != length:
    return CSize(0)

  count


## Completes the minimal stdio contract because Rk-C console writes are direct.
proc fflush*(stream: pointer): cint {.exportc: "fflush", cdecl.} =
  discard stream
  cint(0)


## Terminates the user process when Nim runtime reports a fatal allocation error.
proc runtimeExit*(status: cint) {.exportc: "exit", cdecl, noreturn.} =
  if status < 0:
    sysExit(U64(1))

  sysExit(U64(status))
