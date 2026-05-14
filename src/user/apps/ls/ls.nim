import ../../lib/core/io
import ../../lib/core/args
import ../../lib/core/pathutils
import ../../lib/core/strutils
import ../../lib/core/syscall

const
  LsMaxEntries = 32

var parsedArgs: UserArgs

proc parseLsArgs(arg: cstring, longFormat: var bool): cstring =
  longFormat = false
  if not parseUserArgs(arg, parsedArgs):
    return nil

  var path = resolvePath("")
  var foundPath = false
  var i = U32(0)
  while i < parsedArgs.argc:
    let item = argAt(parsedArgs, i)
    if streq(item, "-l"):
      longFormat = true
    elif item[0] == '-':
      return nil
    else:
      if foundPath:
        return nil

      path = resolvePath(item)
      foundPath = true
      if path == nil:
        return nil

    inc i

  path


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


proc printUsage() =
  write("usage: ls [-l] [path]\n")
  write("  -l    show entry name and size\n")


proc user_start*(arg: cstring) {.exportc, cdecl, noreturn.} =
  if parseUserArgs(arg, parsedArgs) and parsedArgs.argc == 1 and
      streq(argAt(parsedArgs, 0), "--help"):
    printUsage()
    sysExit(0)

  var longFormat: bool
  let path = parseLsArgs(arg, longFormat)
  if path == nil:
    printUsage()
    sysExit(1)

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
