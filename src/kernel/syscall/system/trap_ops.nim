import ../../../lib/syscall_types
import ../../../lib/types
import ../../mm/usercopy

var trapCount* {.volatile.}: SysTrapCount

proc syscallTrapCount*(outEntries: U64): U64 =
  if outEntries == 0:
    return U64(-1'i64)

  let bytes = U64(sizeof(SysTrapCount))
  if copyToUser(outEntries, addr trapCount, bytes) != 0:
    return U64(-1'i64)

  0