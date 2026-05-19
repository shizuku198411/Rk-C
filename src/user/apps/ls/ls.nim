import ../../lib/core/io
import ../../lib/core/args
import ../../lib/core/options
import ../../lib/core/pathutils
import ../../lib/core/syscall

const
  LsMaxEntries = 32

let optionSpecs = [
  OptionSpec(short: 'l', long: cstring(nil)),
  OptionSpec(short: 'a', long: cstring("all")),
]

var
  parsedArgs: UserArgs
  parsedOptions: ParsedOptions

proc parseLsArgs(arg: cstring, longFormat, allEntries: var bool): cstring =
  longFormat = false
  allEntries = false
  if not parseUserArgs(arg, parsedArgs):
    return nil

  if not parseOptions(parsedArgs, optionSpecs, parsedOptions):
    return nil

  if parsedOptions.help or parsedOptions.positionalCount > 1:
    return nil

  longFormat = hasOption(parsedOptions, 'l')
  allEntries = hasOption(parsedOptions, 'a')
  if parsedOptions.positionalCount == 0:
    return resolvePath("")

  resolvePath(positionalAt(parsedOptions, 0))


proc isHiddenEntry(entry: ptr DirEntry): bool =
  entry.name[0] == '.'


proc printLongEntry(entry: ptr DirEntry) =
  write(cast[cstring](addr entry.name[0]))

  if entry.typ == DirEntryTypeDir or entry.typ == DirEntryTypeMount:
    write("/\n")
    return

  write("\t")
  writeUnsigned(U64(entry.size))
  write(" bytes\n")


proc printName(entry: ptr DirEntry) =
  write(cast[cstring](addr entry.name[0]))
  if entry.typ == DirEntryTypeDir or entry.typ == DirEntryTypeMount:
    write("/")


proc printCompact(entries: ptr UncheckedArray[DirEntry], count: int, allEntries: bool) =
  var i = 0
  var col = 0
  while i < count:
    if not allEntries and isHiddenEntry(addr entries[i]):
      inc i
      continue

    printName(addr entries[i])
    inc i
    inc col

    if col == 10:
      write("\n")
      col = 0
    elif i < count:
      write("\t")

  if col != 0:
    write("\n")


proc printUsage() =
  write("usage: ls [-a] [-l] [path]\n")
  write("  -a    show entries starting with .\n")
  write("  -l    show entry name and size\n")


proc user_start*(arg: cstring) {.exportc, cdecl, noreturn.} =
  var longFormat: bool
  var allEntries: bool
  let path = parseLsArgs(arg, longFormat, allEntries)
  if path == nil:
    printUsage()
    if parsedOptions.help:
      sysExit(0)
    else:
      sysExit(1)

  var entries: array[LsMaxEntries, DirEntry]
  let count = sysLs(path, addr entries[0], U64(LsMaxEntries))
  if count < 0:
    write("ls: not found\n")
    sysExit(1)

  if longFormat:
    var i = 0
    while i < int(count):
      if allEntries or not isHiddenEntry(addr entries[i]):
        printLongEntry(addr entries[i])
      inc i
  else:
    printCompact(cast[ptr UncheckedArray[DirEntry]](addr entries[0]), int(count), allEntries)

  sysExit(0)
