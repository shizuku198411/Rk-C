import ../../lib/core/io
import ../../lib/core/args
import ../../lib/core/options
import ../../lib/core/pathutils
import ../../lib/core/syscall

const
  LsChunkEntries = 16

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
  if entry.typ == DirEntryTypeDir or entry.typ == DirEntryTypeMount:
    write("d")
  else:
    write("-")

  let bits = [
    U32(256), U32(128), U32(64),
    U32(32), U32(16), U32(8),
    U32(4), U32(2), U32(1),
  ]
  let chars = ['r', 'w', 'x', 'r', 'w', 'x', 'r', 'w', 'x']
  var bitIndex = 0
  while bitIndex < 9:
    if (entry.mode and bits[bitIndex]) != U32(0):
      writeChar(chars[bitIndex])
    else:
      writeChar('-')
    inc bitIndex

  write("\t")
  writeUnsigned(U64(entry.uid))
  write(":")
  writeUnsigned(U64(entry.gid))
  write("\t")
  writeUnsigned(U64(entry.size))
  write(" bytes")
  write("\t")
  write(cast[cstring](addr entry.name[0]))

  if entry.typ == DirEntryTypeDir or entry.typ == DirEntryTypeMount:
    write("/\n")
  else:
    write("\n")


proc printName(entry: ptr DirEntry) =
  write(cast[cstring](addr entry.name[0]))
  if entry.typ == DirEntryTypeDir or entry.typ == DirEntryTypeMount:
    write("/")


proc printCompactEntry(entry: ptr DirEntry, col: var int) =
  printName(entry)
  inc col

  if col == 10:
    write("\n")
    col = 0
  else:
    write("\t")


proc finishCompact(col: int) =
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

  var entries: array[LsChunkEntries, DirEntry]
  var offset = U64(0)
  var printed = false
  var col = 0

  while true:
    let count = sysLsAt(path, addr entries[0], U64(LsChunkEntries), offset)
    if count < 0:
      if offset == U64(0):
        write("ls: not found\n")
        sysExit(1)
      break

    if count == 0:
      break

    var i = 0
    while i < int(count):
      if allEntries or not isHiddenEntry(addr entries[i]):
        printed = true
        if longFormat:
          printLongEntry(addr entries[i])
        else:
          printCompactEntry(addr entries[i], col)
      inc i

    offset += U64(count)
    if count < I32(LsChunkEntries):
      break

  if not longFormat and printed:
    finishCompact(col)

  sysExit(0)
