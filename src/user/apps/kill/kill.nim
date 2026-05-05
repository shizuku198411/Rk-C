import ../../lib/io
import ../../lib/strutils
import ../../lib/syscall


proc parsePid(arg: cstring): I32 =
  if isEmpty(arg):
    return -1

  var i = 0
  var pid = I32(0)
  while arg[i] >= '0' and arg[i] <= '9':
    pid = pid * 10 + I32(ord(arg[i]) - ord('0'))
    inc i

  if arg[i] != '\0':
    return -1

  pid


proc user_start*(arg: cstring) {.exportc, cdecl, noreturn.} =
  let pid = parsePid(arg)
  if pid <= 0:
    write("usage: kill <pid>\n")
    sysExit(1)

  if sysKill(pid) != 0:
    write("kill: failed\n")
    sysExit(1)

  sysExit(0)
