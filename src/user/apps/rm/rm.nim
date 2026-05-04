import ../../lib/syscall

proc user_start*(arg: cstring) {.exportc, cdecl, noreturn.} =
  if isEmpty(arg):
    write("usage: rm <path>\n")
    sysExit(1)

  let rc = sysUnlink(arg)
  if rc != 0:
    write("rm: failed\n")
    sysExit(1)
  sysExit(0)
