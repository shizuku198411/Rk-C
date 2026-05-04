import ../../lib/io
import ../../lib/strutils
import ../../lib/syscall

proc user_start*(arg: cstring) {.exportc, cdecl, noreturn.} =
  if isEmpty(arg):
    write("usage: mkdir <path>\n")
    sysExit(1)

  let rc = sysMkdir(arg)
  if rc != 0:
    write("mkdir: failed\n")
    sysExit(1)
  sysExit(0)
