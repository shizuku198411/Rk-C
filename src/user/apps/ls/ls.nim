import ../../lib/syscall

proc user_start*(arg: cstring) {.exportc, cdecl, noreturn.} =
  var path = arg
  if path == nil or path[0] == '\0':
    path = "/"

  discard sysLs(path)
  sysExit(0)
