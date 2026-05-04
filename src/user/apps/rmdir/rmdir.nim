import ../../lib/syscall

proc user_start*(arg: cstring) {.exportc, cdecl, noreturn.} =
  if isEmpty(arg):
    write("usage: rmdir <path>\n")
    sysExit(1)

  let rc = sysRmdir(arg)
  if rc != 0:
    write("rmdir: failed\n")
    sysExit(1)
  sysExit(0)
