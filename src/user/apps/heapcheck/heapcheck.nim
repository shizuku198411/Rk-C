## Validates the initial user heap, small allocations, and reset behavior.
import ../../lib/core/heap
import ../../lib/core/io
import ../../lib/core/strutils
import ../../lib/core/syscall


proc fail(msg: cstring) {.noreturn.} =
  write("heapcheck: ")
  write(msg)
  write("\n")
  sysExit(1)


proc user_start*(arg: cstring) {.exportc, cdecl, noreturn.} =
  if cstringEq(arg, cstring"--help"):
    write("usage: heapcheck\n")
    sysExit(0)

  let initial = sysSbrk(0)
  if initial < 0:
    fail(cstring"sbrk(0) failed")

  let initialBreak = U64(initial)
  if not userResetHeap():
    fail(cstring"reset failed")

  let afterReset = sysSbrk(0)
  if afterReset < 0 or U64(afterReset) != initialBreak:
    fail(cstring"reset mismatch")

  let p1 = userAlloc(64)
  if p1 == nil:
    fail(cstring"alloc failed")

  let buf1 = cast[ptr UncheckedArray[char]](p1)
  for i in 0 ..< 64:
    buf1[i] = char(ord('A') + (i mod 26))
  for i in 0 ..< 64:
    if buf1[i] != char(ord('A') + (i mod 26)):
      fail(cstring"alloc content mismatch")

  let p2 = userAlloc(4096)
  if p2 == nil:
    fail(cstring"page-crossing alloc failed")

  let buf2 = cast[ptr UncheckedArray[char]](p2)
  buf2[0] = 'Z'
  buf2[4095] = 'Y'
  if buf2[0] != 'Z' or buf2[4095] != 'Y':
    fail(cstring"page-crossing verify failed")

  if not userResetHeap():
    fail(cstring"reset failed")

  let reset2 = sysSbrk(0)
  if reset2 < 0 or U64(reset2) != initialBreak:
    fail(cstring"reset mismatch")

  let p3 = userAlloc(8192)
  if p3 == nil:
    fail(cstring"multi-page alloc failed")

  let buf3 = cast[ptr UncheckedArray[char]](p3)
  buf3[0] = 'A'
  buf3[4096] = 'B'
  buf3[8191] = 'C'

  if buf3[0] != 'A' or buf3[4096] != 'B' or buf3[8191] != 'C':
    fail(cstring"multi-page verify failed")

  let wrapAlloc = userAlloc(high(U64) - U64(3))
  if wrapAlloc != nil:
    fail(cstring"wrap alloc succeeded")

  let overflowAlloc = userAlloc(U64(1) shl U64(63))
  if overflowAlloc != nil:
    fail(cstring"overflow alloc succeeded")

  write("heapcheck: ok\n")
  sysExit(0)
