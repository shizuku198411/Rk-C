import ../../lib/core/args
import ../../lib/core/io
import ../../lib/core/pathutils
import ../../lib/core/strutils
import ../../lib/core/syscall


var parsedArgs: UserArgs


proc printUsage() =
  write("usage: chmod <octal-mode> <path>\n")
  write("       chmod --help\n")


proc parseOctalMode(s: cstring, mode: var U32): bool =
  if s == nil or s[0] == '\0':
    return false

  var value = U32(0)
  var pos = U32(0)
  while s[pos] != '\0':
    if s[pos] < '0' or s[pos] > '7':
      return false
    value = value * U32(8) + U32(ord(s[pos]) - ord('0'))
    if value > U32(0o777):
      return false
    inc pos

  mode = value
  true


proc user_start*(arg: cstring) {.exportc, cdecl, noreturn.} =
  if not parseUserArgs(arg, parsedArgs):
    printUsage()
    sysExit(1)

  if parsedArgs.argc == 1 and cstringEq(argAt(parsedArgs, 0), "--help"):
    printUsage()
    sysExit(0)

  if parsedArgs.argc != 2:
    printUsage()
    sysExit(1)

  var mode: U32
  if not parseOctalMode(argAt(parsedArgs, 0), mode):
    write("chmod: invalid mode\n")
    sysExit(1)

  let path = resolvePath(argAt(parsedArgs, 1))
  if path == nil:
    write("chmod: path too long\n")
    sysExit(1)

  if sysChmod(path, mode) != 0:
    write("chmod: failed\n")
    sysExit(1)

  sysExit(0)
