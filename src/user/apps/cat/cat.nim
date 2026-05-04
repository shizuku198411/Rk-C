import ../../lib/syscall

proc user_start*(arg: cstring) {.exportc, cdecl, noreturn.} =
  if isEmpty(arg):
    write("usage: cat <path>\n")
    sysExit(1)

  let rc = sysCat(arg)
  if rc != 0:
    write("cat: failed\n")
    sysExit(1)
  sysExit(0)
