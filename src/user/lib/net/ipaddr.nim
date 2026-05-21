## Parses and prints IPv4 addresses.
import ../core/io
import ../core/syscall
import ./netutls


## Parses ipv4 addr.
proc parseIpv4Addr*(arg: cstring, ip: var U32): bool =
  if arg == nil:
    return false

  var pos = U32(0)
  if not parseIpv4(arg, pos, ip):
    return false

  arg[pos] == '\0'


## Writes ipv4 addr.
proc writeIpv4Addr*(value: U32) =
  writeUnsigned(U64((value shr 24) and 0xff'u32))
  writeChar('.')
  writeUnsigned(U64((value shr 16) and 0xff'u32))
  writeChar('.')
  writeUnsigned(U64((value shr 8) and 0xff'u32))
  writeChar('.')
  writeUnsigned(U64(value and 0xff'u32))
