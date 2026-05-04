import ../../lib/syscall

proc user_start*(arg: cstring) {.exportc, cdecl, noreturn.} =
  discard arg
  discard sysPs()
  sysExit(0)
