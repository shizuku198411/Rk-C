## Prints the current process environment variables.
import ../../lib/core/args
import ../../lib/core/app
import ../../lib/core/io
import ../../lib/core/syscall


var
  parsedArgs: UserArgs
  entries: array[SysEnvMaxEntries, SysEnvEntry]


## Prints env usage information.
proc printUsage() =
  write("usage: env\n")
  write("       env --help\n")


## Prints one environment entry as KEY=VALUE.
proc printEnvEntry(entry: SysEnvEntry) =
  write(cast[cstring](addr entry.key[0]))
  write("=")
  write(cast[cstring](addr entry.value[0]))
  write("\n")


## Reads and prints the current environment.
proc user_start*(arg: cstring) {.exportc, cdecl, noreturn.} =
  parseArgsOrExit(arg, parsedArgs, printUsage)
  exitIfHelp(parsedArgs, printUsage)
  requireArgc(parsedArgs, U32(0), printUsage)

  let count = sysGetEnv(addr entries[0])
  if count < 0:
    write("env: failed to read environment\n")
    sysExit(1)

  var i = I32(0)
  while i < count:
    if entries[U32(i)].used != U32(0):
      printEnvEntry(entries[U32(i)])
    inc i

  sysExit(0)
