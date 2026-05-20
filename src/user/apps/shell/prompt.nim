import ../../lib/core/io
import ../../lib/core/syscall
import ./state


proc printPrompt*() =
  if sysGetCwd(addr cwdBuf[0], U64(SysProcessCwdMax)) < 0:
    cwdBuf[0] = '/'
    cwdBuf[1] = '\0'

  let uid = sysGetUid()
  var username: cstring
  if uid == 0:
    username = "root"
  elif uid == 1000:
    username = "user"

  write(PromptOrange)
  write(username)
  write(PromptReset)
  write("@")
  write(PromptOrange)
  write("Rk-C")
  write(PromptReset)
  write(":")
  write(PromptOrange)
  write(cast[cstring](addr cwdBuf[0]))
  write(PromptReset)
  write("$ ")
