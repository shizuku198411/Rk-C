import ../../lib/io
import ../../lib/syscall

const
  LsMaxEntries = 32


proc skipSpaces(s: cstring, pos: var U64) =
  while s != nil and s[pos] == ' ':
    inc pos


proc tokenIsLongOption(s: cstring, pos: U64): bool =
  s != nil and s[pos] == '-' and s[pos + 1] == 'l' and
    (s[pos + 2] == '\0' or s[pos + 2] == ' ')


proc restCString(s: cstring, pos: U64): cstring =
  cast[cstring](unsafeAddr s[pos])


proc parseArgs(arg: cstring, longFormat: var bool): cstring =
  longFormat = false
  if arg == nil:
    return "/"

  var pos = U64(0)
  skipSpaces(arg, pos)
  if arg[pos] == '\0':
    return "/"

  if tokenIsLongOption(arg, pos):
    longFormat = true
    pos += 2
    skipSpaces(arg, pos)
    if arg[pos] == '\0':
      return "/"

  restCString(arg, pos)


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


proc printCompact(entries: ptr UncheckedArray[DirEntry], count: int) =
  var i = 0
  var col = 0
  while i < count:
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


proc user_start*(arg: cstring) {.exportc, cdecl, noreturn.} =
  var longFormat: bool
  let path = parseArgs(arg, longFormat)

  var entries: array[LsMaxEntries, DirEntry]
  let count = sysLs(path, addr entries[0], U64(LsMaxEntries))
  if count < 0:
    write("ls: not found\n")
    sysExit(1)

  if longFormat:
    var i = 0
    while i < int(count):
      printLongEntry(addr entries[i])
      inc i
  else:
    printCompact(cast[ptr UncheckedArray[DirEntry]](addr entries[0]), int(count))

  sysExit(0)
