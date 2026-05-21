## Renders the colored shell prompt from the current user and cwd.
import ../../lib/core/io
import ../../lib/core/passwd
import ../../lib/core/syscall
import ../../lib/core/userdb
import ./state


## Prints the prompt as user@Rk-C:<cwd>$ with highlighted fields.
proc printPrompt*() =
  if sysGetCwd(addr cwdBuf[0], U64(SysProcessCwdMax)) < 0:
    cwdBuf[0] = '/'
    cwdBuf[1] = '\0'

  let uid = sysGetUid()
  var entry: PasswdEntry
  let username =
    if resolveUid(uid, entry):
      cast[cstring](addr entry.name[0])
    else:
      cstring"unknown"

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
