import ../../lib/core/io
import ../../lib/core/strutils
import ../../lib/core/syscall

proc user_start*(arg: cstring) {.exportc, cdecl, noreturn.} =
  if isEmpty(arg):
    write("usage: stracectl <on|off|<pid>>\n")
    sysExit(1)
  
  var pid: U64

    
  if streq(arg, "on"):
    if sysTraceCtl(TraceOn, 0) < 0:
      write("trace all failed\n")
      sysExit(1)
    write("strace on\n")

  elif streq(arg, "off"):
    if sysTraceCtl(TraceOff, 0) < 0:
      write("trace off failed\n")
      sysExit(1)
    write("strace off\n")

  else:
    if not parseU64(arg, pid):
      write("invalid pid\n")
      sysExit(1)
    if sysTraceCtl(TracePid, pid) < 0:
      write("strace ")
      writeUnsigned(pid)
      write(" failed\n")
      sysExit(1)
    write("strace ")
    writeUnsigned(pid)
    write(" on\n")


  sysExit(0)
