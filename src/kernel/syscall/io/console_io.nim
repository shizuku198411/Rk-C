import ../../../lib/types
import ../../../arch/riscv64/arch
import ../../dev/console
import ../../mm/usercopy
import ../../task/process


proc syscallConsoleWrite*(buf: U64, len: U64): U64 =
  if len == 0:
    return 0
  if not validateUserRange(buf, len, false):
    return U64(-1'i64)

  let old = arch.readSstatus()
  arch.writeSstatus(old or SstatusSum)
  let p = cast[ptr UncheckedArray[char]](buf)
  var i = U64(0)
  while i < len:
    putChar(p[i])
    inc i
  arch.writeSstatus(old)
  len


proc syscallConsoleRead*(buf: U64, len: U64): U64 =
  if len == 0:
    return 0
  if not validateUserRange(buf, len, true):
    return U64(-1'i64)

  let p = cast[ptr UncheckedArray[char]](buf)
  var i = U64(0)
  while i < len:
    let ch = tryGetChar()
    if ch < 0:
      sleepCurrentForInput()
      continue

    let old = arch.readSstatus()
    arch.writeSstatus(old or SstatusSum)
    p[i] = char(ch and 0xff)
    arch.writeSstatus(old)
    inc i
  i
