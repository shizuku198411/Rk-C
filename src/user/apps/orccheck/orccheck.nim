## Validates Nim ORC-managed allocations backed by the Rk-C user process heap.
{.warning[UnusedImport]: off.}

import ../../lib/runtime/orc_osalloc
import ../../lib/core/io
import ../../lib/core/strutils
import ../../lib/core/syscall
import ../../../lib/types


type
  ManagedNode = ref object
    value: int
    label: string
    next: ManagedNode


## Prints a validation failure and terminates the test process.
proc fail(msg: cstring) {.noreturn.} =
  write("orccheck: ")
  write(msg)
  write("\n")
  sysExit(1)


## Verifies released blocks are reused and trailing heap storage is returned.
proc validateAllocatorRelease(): bool =
  let initialBreak = sysSbrk(0)
  if initialBreak < 0:
    return false

  let first = orc_osalloc.malloc(CSize(8192))
  if first == nil:
    return false

  let second = orc_osalloc.malloc(CSize(4096))
  if second == nil:
    orc_osalloc.free(first)
    return false

  let grownBreak = sysSbrk(0)
  if grownBreak <= initialBreak:
    orc_osalloc.free(first)
    orc_osalloc.free(second)
    return false

  orc_osalloc.free(first)
  let reused = orc_osalloc.malloc(CSize(4096))
  if reused != first:
    orc_osalloc.free(reused)
    orc_osalloc.free(second)
    return false

  orc_osalloc.free(reused)
  orc_osalloc.free(second)
  sysSbrk(0) == initialBreak


## Verifies heap-backed mutation and growth for a managed string.
proc validateString(): bool =
  var value = ""
  for i in 0 ..< 48:
    discard i
    value.add("rk")

  value.len == 96 and value[0] == 'r' and value[95] == 'k'


## Verifies heap-backed growth and contents for a managed sequence.
proc validateSequence(): bool =
  var values: seq[int] = @[]
  var expected = 0

  for i in 0 ..< 128:
    values.add(i * 3)
    expected += i * 3

  var actual = 0
  for value in values:
    actual += value

  values.len == 128 and actual == expected


## Verifies allocation and release paths for reference-counted ORC objects.
proc validateReferences(): bool =
  var head = ManagedNode(value: 1, label: "head")
  head.next = ManagedNode(value: 2, label: "tail")

  let valid = head.label == "head" and head.next != nil and
    head.next.value == 2 and head.next.label == "tail"
  head = nil
  valid


## Runs the ORC userland allocation validation application.
proc user_start*(arg: cstring) {.exportc, cdecl, noreturn.} =
  if cstringEq(arg, cstring"--help"):
    write("usage: orccheck\n")
    sysExit(0)

  if not validateAllocatorRelease():
    fail(cstring"allocator release failed")
  write("orccheck: allocator release ok\n")

  if not validateString():
    fail(cstring"string failed")
  write("orccheck: string ok\n")

  if not validateSequence():
    fail(cstring"seq failed")
  write("orccheck: seq ok\n")

  if not validateReferences():
    fail(cstring"ref failed")
  write("orccheck: ref ok\n")

  write("orccheck: ok\n")
  sysExit(0)
