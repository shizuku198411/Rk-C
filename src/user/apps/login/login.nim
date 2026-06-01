## Provides the login loop that authenticates users and starts their shell.
import ../../lib/core/args
import ../../lib/core/app
import ../../lib/core/io
import ../../lib/core/passwd
import ../../lib/core/strutils
import ../../lib/core/syscall
import ../../lib/core/userdb


var
  parsedArgs: UserArgs
  usernameBuf: array[LoginLineMax, char]
  passwordBuf: array[LoginLineMax, char]


## Clears the current terminal line.
proc clearScreen() =
  write("\x1b[2J\x1b[H")


## Prints login usage information.
proc printUsage() =
  write("usage: login\n")


## Starts a shell process with the authenticated user's identity and home cwd.
proc runShell(entry: PasswdEntry) =
  discard sysSetCwd(cast[cstring](addr entry.home[0]))

  let shellPid = sysExecAs(cstring"/bin/shell", nil, entry.uid, entry.gid)
  if shellPid < 0:
    write("login: failed to start shell\n")
    return

  discard sysWait(shellPid)


## Runs the login prompt forever and respawns a shell after logout.
proc user_start*(arg: cstring) {.exportc, cdecl, noreturn.} =
  parseArgsOrExit(arg, parsedArgs, printUsage)
  exitIfHelp(parsedArgs, printUsage)
  requireArgc(parsedArgs, U32(0), printUsage)

  while true:
    write("login: ")
    let username = readLoginLine(usernameBuf, true)
    write("password: ")
    let password = readLoginLine(passwordBuf, false)

    var entry: PasswdEntry
    if authenticateUser(username, password, entry):
      write("\n")
      runShell(entry)
      write("\n")
      clearScreen()
      continue

    if not isEmpty(username):
      write("incorrect username or password\n\n")
