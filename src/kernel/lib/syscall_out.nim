import ../../lib/types
import ../mm/usercopy


proc copyOutObject*[T](outVal: U64, value: var T): bool =
  outVal != 0 and copyToUser(outVal, addr value, U64(sizeof(T))) == 0


proc copyOutBuffer*(outVal: U64, src: pointer, size: U64): bool =
  outVal != 0 and copyToUser(outVal, src, size) == 0
