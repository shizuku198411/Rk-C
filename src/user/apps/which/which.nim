## Prints the executable path selected by the shared command resolver.
import ../../lib/core/args
import ../../lib/core/app
import ../../lib/core/command_resolver
import ../../lib/core/io
import ../../lib/core/pathutils
import ../../lib/core/syscall


var
  parsedArgs: UserArgs
  resolvedPath: array[PathMax, char]


## Prints which usage information.
proc printUsage() =
  write("usage: which <command> [command...]\n")


## Resolves each requested command and prints its selected executable path.
proc user_start*(arg: cstring) {.exportc, cdecl, noreturn.} =
  parseArgsOrExit(arg, parsedArgs, printUsage)
  exitIfHelp(parsedArgs, printUsage)
  requireMinArgc(parsedArgs, U32(1), printUsage)

  var failed = false
  var i = U32(0)
  while i < parsedArgs.argc:
    let command = argAt(parsedArgs, i)
    let status = resolveCommandInto(
      command,
      cast[ptr UncheckedArray[char]](addr resolvedPath[0]),
      PathMax,
    )
    if status == CommandResolved:
      write(cast[cstring](addr resolvedPath[0]))
      write("\n")
    elif status == CommandPathTooLong:
      write("which: path too long: ")
      write(command)
      write("\n")
      failed = true
    else:
      write("which: not found: ")
      write(command)
      write("\n")
      failed = true

    inc i

  if failed:
    sysExit(1)

  sysExit(0)
