## Changes an account password after reading and confirming a new secret.
import ../../lib/core/args
import ../../lib/core/app
import ../../lib/core/io
import ../../lib/core/passwd
import ../../lib/core/strutils
import ../../lib/core/syscall
import ../../lib/core/userdb


var
  parsedArgs: UserArgs
  passwordBuf: array[LoginLineMax, char]
  confirmBuf: array[LoginLineMax, char]


## Prints passwd usage information.
proc printUsage() =
  write("usage: passwd <user>\n")
  write("       passwd --help\n")


## Returns whether two password input buffers contain the same C string.
proc passwordMatches(a, b: cstring): bool =
  cstringEq(a, b)


## Reads the new password twice and asks userd to persist the updated hash.
proc user_start*(arg: cstring) {.exportc, cdecl, noreturn.} =
  parseArgsOrExit(arg, parsedArgs, printUsage)
  exitIfHelp(parsedArgs, printUsage)
  requireArgc(parsedArgs, U32(1), printUsage)

  var entry: PasswdEntry
  if not resolveUser(argAt(parsedArgs, 0), entry):
    write("passwd: unknown user\n")
    sysExit(1)

  write("new password: ")
  let password = readLoginLine(passwordBuf, false)
  if isEmpty(password):
    write("passwd: empty password\n")
    sysExit(1)

  write("confirm password: ")
  let confirm = readLoginLine(confirmBuf, false)
  if not passwordMatches(password, confirm):
    write("passwd: password mismatch\n")
    sysExit(1)

  if not setUserPassword(entry.uid, password):
    write("passwd: failed\n")
    sysExit(1)

  write("passwd: password updated\n")
  sysExit(0)
