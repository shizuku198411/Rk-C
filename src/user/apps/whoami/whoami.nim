## Prints the current user name
import ../../lib/core/args
import ../../lib/core/io
import ../../lib/core/syscall
import ../../lib/core/strutils
import ../../lib/core/passwd
import ../../lib/core/userdb


var parsedArgs: UserArgs


## Prints whoami usage information.
proc printUsage() = 
  write("usage: whoami\n")
  write("       whoami --help\n")


## Reads current uid and resolve username
proc user_start*(arg: cstring) {.exportc, cdecl, noreturn.} =
  if not parseUserArgs(arg, parsedArgs):
    printUsage()
    sysExit(1)
  
  if parsedArgs.argc == 1 and cstringEq(argAt(parsedArgs, 0), "--help"):
    printUsage()
    sysExit(0)
  
  if parsedArgs.argc != 0:
    printUsage()
    sysExit(1)
  
  let uid = sysGetUid()
  var entry: PasswdEntry
  if not resolveUid(uid, entry):
    write("failed to resolve username\n")
    sysExit(1)
  
  write(cast[cstring](addr entry.name[0]))
  write("\n")

  sysExit(0)
