import ../../lib/core/io
import ../../lib/core/passwd
import ../../lib/core/strutils
import ../../lib/core/syscall
import ../../lib/core/userdb


const
  LoginLineMax = 64


var
  usernameBuf: array[LoginLineMax, char]
  passwordBuf: array[LoginLineMax, char]


proc clearBuf(buf: var array[LoginLineMax, char]) =
  var i = 0
  while i < LoginLineMax:
    buf[i] = '\0'
    inc i


proc readLoginLine(buf: var array[LoginLineMax, char], echo: bool): cstring =
  clearBuf(buf)

  var len = 0
  while true:
    let ch = readChar()
    if ch == '\r' or ch == '\n':
      buf[len] = '\0'
      write("\n")
      return cast[cstring](addr buf[0])

    if ch == '\b' or ch == char(127):
      if len > 0:
        dec len
        buf[len] = '\0'
        if echo:
          write("\b \b")

      continue

    if ch < ' ' or ch > '~':
      continue

    if len < LoginLineMax - 1:
      buf[len] = ch
      inc len
      buf[len] = '\0'
      if echo:
        writeChar(ch)


proc runShell(entry: PasswdEntry) {.noreturn.} =
  if sysSetUser(entry.uid, entry.gid) != 0:
    write("login: failed to set user\n")
    sysExit(1)

  discard sysSetCwd(cast[cstring](addr entry.home[0]))

  let shellPid = sysExec(cstring"/bin/shell", nil, false)
  if shellPid < 0:
    write("login: failed to start shell\n")
    sysExit(1)

  discard sysWait(shellPid)
  sysExit(0)


proc user_start*(arg: cstring) {.exportc, cdecl, noreturn.} =
  if cstringEq(arg, cstring"--help"):
    write("usage: login\n")
    sysExit(0)

  while true:
    write("login: ")
    let username = readLoginLine(usernameBuf, true)
    write("password: ")
    let password = readLoginLine(passwordBuf, false)

    var entry: PasswdEntry
    if authenticateUser(username, password, entry):
      runShell(entry)

    if not isEmpty(username):
      write("login: incorrect username or password\n")
