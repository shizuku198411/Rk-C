## Provides shared helpers for user command argument validation and exits.
import ./args
import ./io
import ./strutils
import ./syscall

type
  UsageProc* = proc()


## Returns true when argv is exactly "--help".
proc isHelp*(parsedArgs: var UserArgs): bool =
  parsedArgs.argc == U32(1) and cstringEq(argAt(parsedArgs, U32(0)), cstring("--help"))


## Prints usage and exits with the requested status.
proc printUsageAndExit*(printUsage: UsageProc, status: U64) {.noreturn.} =
  printUsage()
  sysExit(status)


## Prints a message and exits with failure.
proc failExit*(message: cstring) {.noreturn.} =
  write(message)
  sysExit(1)


## Parses raw app args or exits with usage on parse failure.
proc parseArgsOrExit*(arg: cstring, parsedArgs: var UserArgs, printUsage: UsageProc) =
  if not parseUserArgs(arg, parsedArgs):
    printUsageAndExit(printUsage, U64(1))


## Exits with usage when argv is exactly "--help".
proc exitIfHelp*(parsedArgs: var UserArgs, printUsage: UsageProc) =
  if isHelp(parsedArgs):
    printUsageAndExit(printUsage, U64(0))


## Requires exactly argc args, otherwise exits with usage.
proc requireArgc*(parsedArgs: var UserArgs, expected: U32, printUsage: UsageProc) =
  if parsedArgs.argc != expected:
    printUsageAndExit(printUsage, U64(1))


## Requires at least min argc args, otherwise exits with usage.
proc requireMinArgc*(parsedArgs: var UserArgs, minArgc: U32, printUsage: UsageProc) =
  if parsedArgs.argc < minArgc:
    printUsageAndExit(printUsage, U64(1))


## Requires at most max argc args, otherwise exits with usage.
proc requireMaxArgc*(parsedArgs: var UserArgs, maxArgc: U32, printUsage: UsageProc) =
  if parsedArgs.argc > maxArgc:
    printUsageAndExit(printUsage, U64(1))


## Requires argc to be within a closed range, otherwise exits with usage.
proc requireArgcRange*(parsedArgs: var UserArgs, minArgc, maxArgc: U32, printUsage: UsageProc) =
  if parsedArgs.argc < minArgc or parsedArgs.argc > maxArgc:
    printUsageAndExit(printUsage, U64(1))
