## Provides helpers for formatting syscall output inside the kernel.
import ../../lib/types
import ../mm/usercopy


## Copies out object.
proc copyOutObject*[T](outVal: U64, value: var T): bool =
  outVal != 0 and copyToUser(outVal, addr value, U64(sizeof(T))) == 0


## Copies out buffer.
proc copyOutBuffer*(outVal: U64, src: pointer, size: U64): bool =
  outVal != 0 and copyToUser(outVal, src, size) == 0
