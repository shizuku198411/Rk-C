import ../../lib/core/io
import ../../lib/core/syscall
import ./state


proc printPrompt*() =
  if sysGetCwd(addr cwdBuf[0], U64(SysProcessCwdMax)) < 0:
    cwdBuf[0] = '/'
    cwdBuf[1] = '\0'

  write(PromptOrange)
  write("Rk-C")
  write(PromptReset)
  write(":")
  write(PromptOrange)
  write(cast[cstring](addr cwdBuf[0]))
  write(PromptReset)
  write("$ ")
