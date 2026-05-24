## Prints process information through the process manager service.
{.warning[UnusedImport]: off.}

import ../../lib/runtime/orc_osalloc
import ../../lib/core/io
import ../../lib/ipc/packet_data
import ../../lib/ipc/ipc_request
import ../../lib/ipc/service_client
import ../../lib/core/args
import ../../lib/core/options
import ../../lib/core/syscall
import ../../lib/core/passwd
import ../../lib/core/group
import ../../lib/core/userdb

const
  PsMaxEntries = int(SysProcessMaxSlots)

let optionSpecs = [
  OptionSpec(short: 'f', long: cstring(nil)),
  OptionSpec(short: 'e', long: cstring(nil)),
  OptionSpec(short: 'l', long: cstring(nil)),
]

var
  entries: seq[SysProcessInfo] = @[]
  parsedArgs: UserArgs
  parsedOptions: ParsedOptions


## Includes procmgtd request handling and the managed process snapshot workspace.
include ./internal/process_client


## Includes process filtering and ORC-managed table rendering.
include ./internal/rendering


## Prints ps usage information.
proc printUsage() =
  write("usage: ps [-f] [-e] [-l]\n")
  write("  -f    show pid, ppid, uid, gid, state, mode, and exe\n")
  write("  -e    show all process slots\n")
  write("  -l    show cpu and memory usage\n")


## Parses ps options, requests process data, and prints the table.
proc user_start*(arg: cstring) {.exportc, cdecl, noreturn.} =
  if not parseUserArgs(arg, parsedArgs):
    printUsage()
    sysExit(1)

  if not parseOptions(parsedArgs, optionSpecs, parsedOptions):
    printUsage()
    sysExit(1)

  if parsedOptions.help:
    printUsage()
    sysExit(0)

  if parsedOptions.positionalCount != 0:
    printUsage()
    sysExit(1)

  let full = hasOption(parsedOptions, 'f')
  let every = hasOption(parsedOptions, 'e')
  let longFormat = hasOption(parsedOptions, 'l')

  if not initManagedStorage():
    write("ps: failed to allocate workspace\n")
    sysExit(1)

  let count = requestProcessList(I32(PsMaxEntries), U64(0))
  if count < 0:
    write("ps: failed\n")
    sysExit(1)

  printProcesses(count, full, every, longFormat)

  sysExit(0)
