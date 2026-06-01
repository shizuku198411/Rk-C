## Provides kernel helpers for copying user path C strings into fixed buffers.
import ../../lib/types
import ../mm/usercopy


## Copies a user pointer C string into a fixed path buffer.
proc copyUserPath*(pathVal: U64, dst: var openArray[char]): bool =
  if pathVal == U64(0) or dst.len == 0:
    return false

  copyUserCString(addr dst[0], pathVal, U64(dst.len)) >= 0


## Copies two user pointer C strings into fixed path buffers.
proc copyUserPathPair*(firstVal, secondVal: U64, firstDst, secondDst: var openArray[char]): bool =
  copyUserPath(firstVal, firstDst) and copyUserPath(secondVal, secondDst)
