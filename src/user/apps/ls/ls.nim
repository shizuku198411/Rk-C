## Lists directory entries in compact or long format.
import ../../lib/core/io
import ../../lib/core/args
import ../../lib/core/app
import ../../lib/core/options
import ../../lib/core/pathutils
import ../../lib/core/syscall
import ../../lib/core/passwd
import ../../lib/core/group
import ../../lib/core/userdb

const
  LsChunkEntries = 16

let optionSpecs = [
  OptionSpec(short: 'l', long: cstring(nil)),
  OptionSpec(short: 'a', long: cstring("all")),
]

var
  parsedArgs: UserArgs
  parsedOptions: ParsedOptions


## Prints ls usage information.
proc printUsage() =
  write("usage: ls [-a] [-l] [path]\n")
  write("  -a    show entries starting with .\n")
  write("  -l    show entry name and size\n")


## Parses ls options and resolves the optional target path.
proc parseLsArgs(arg: cstring, longFormat, allEntries: var bool): cstring =
  longFormat = false
  allEntries = false
  parseArgsOrExit(arg, parsedArgs, printUsage)

  if not parseOptions(parsedArgs, optionSpecs, parsedOptions):
    return nil

  if parsedOptions.help or parsedOptions.positionalCount > 1:
    return nil

  longFormat = hasOption(parsedOptions, 'l')
  allEntries = hasOption(parsedOptions, 'a')
  if parsedOptions.positionalCount == 0:
    return resolvePath("")

  resolvePath(positionalAt(parsedOptions, 0))


## Returns true when a directory entry should be hidden by default.
proc isHiddenEntry(entry: ptr DirEntry): bool =
  entry.name[0] == '.'


## Prints one directory entry with permissions, owner, size, and name.
proc printLongEntry(entry: ptr DirEntry) =
  var modeBuf: array[10, char]

  if entry.typ == DirEntryTypeDir or entry.typ == DirEntryTypeMount:
    modeBuf[0] = 'd'
  else:
    modeBuf[0] = '-'

  let bits = [
    U32(256), U32(128), U32(64),
    U32(32), U32(16), U32(8),
    U32(4), U32(2), U32(1),
  ]
  let chars = ['r', 'w', 'x', 'r', 'w', 'x', 'r', 'w', 'x']

  var bitIndex = 0
  while bitIndex < 9:
    if (entry.mode and bits[bitIndex]) != U32(0):
      modeBuf[bitIndex + 1] = chars[bitIndex]
    else:
      modeBuf[bitIndex + 1] = '-'
    inc bitIndex

  writeBuffer(addr modeBuf[0], 10)

  write("\t")
  var
    userEntry: PasswdEntry
    groupEntry: GroupEntry
  if resolveUid(entry.uid, userEntry):
    write(cast[cstring](addr userEntry.name[0]))
  else:
    writeUnsigned(U64(entry.uid))
  write(":")
  if resolveGid(entry.gid, groupEntry):
    write(cast[cstring](addr groupEntry.name[0]))
  else:
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


## Prints only the entry name and a trailing slash for directories.
proc printName(entry: ptr DirEntry) =
  write(cast[cstring](addr entry.name[0]))
  if entry.typ == DirEntryTypeDir or entry.typ == DirEntryTypeMount:
    write("/")


## Prints one compact entry and tracks ten-column line wrapping.
proc printCompactEntry(entry: ptr DirEntry, col: var int) =
  printName(entry)
  inc col

  if col == 10:
    write("\n")
    col = 0
  else:
    write("\t")


## Emits the final newline for compact output when needed.
proc finishCompact(col: int) =
  if col != 0:
    write("\n")


## Lists the requested directory by reading entries in chunks.
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
