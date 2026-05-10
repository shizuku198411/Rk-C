import ../core/syscall
import ../core/strutils


proc parseDecimalU32(s: cstring, pos: var U32, value: var U32): bool =
  var v: U32 = 0
  var found = false

  while isDigit(s[pos]):
    found = true
    v = v * U32(10) + U32(ord(s[pos]) - ord('0'))
    pos += U32(1)

  if not found:
    return false

  value = v
  true


proc parseIpv4*(s: cstring, pos: var U32, outIp: var U32): bool =
  var a, b, c, d: U32

  if not parseDecimalU32(s, pos, a):
    return false
  if s[pos] != '.':
    return false
  pos += 1.U32

  if not parseDecimalU32(s, pos, b):
    return false
  if s[pos] != '.':
    return false
  pos += 1.U32

  if not parseDecimalU32(s, pos, c):
    return false
  if s[pos] != '.':
    return false
  pos += 1.U32

  if not parseDecimalU32(s, pos, d):
    return false

  if a > 255.U32 or b > 255.U32 or c > 255.U32 or d > 255.U32:
    return false

  outIp =
    (a shl 24) or
    (b shl 16) or
    (c shl 8) or
    d

  true
