## Renders the colored shell prompt from the current user and cwd.
import ../../lib/core/io
import ../../lib/core/passwd
import ../../lib/core/strutils
import ../../lib/core/syscall
import ../../lib/core/userdb
import ./state


## Replaces the leading home path in cwdBuf with '~' for prompt rendering.
proc abbreviateHomeInCwd() =
  if sysGetEnv(addr envBuf[0], cstring("HOME")) <= 0:
    return

  let
    cwd = cast[cstring](addr cwdBuf[0])
    home = cast[cstring](addr envBuf[0])
  if cstringEq(cwd, home):
    cwdBuf[0] = '~'
    cwdBuf[1] = '\0'
    return

  let homeLen = cstrlen(home)
  if homeLen <= U64(1):
    return
  if cwd[homeLen] != '/':
    return
  if not startsWithPrefix(cwd, home):
    return

  cwdBuf[0] = '~'
  var dst = U64(1)
  var src = homeLen
  while dst + U64(1) < U64(SysProcessCwdMax) and cwdBuf[src] != '\0':
    cwdBuf[dst] = cwdBuf[src]
    inc dst
    inc src
  cwdBuf[dst] = '\0'


## Prints the prompt as user@Rk-C:<cwd>$ with highlighted fields.
proc printPrompt*() =
  if sysGetCwd(addr cwdBuf[0], U64(SysProcessCwdMax)) < 0:
    cwdBuf[0] = '/'
    cwdBuf[1] = '\0'
  
  abbreviateHomeInCwd()

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
