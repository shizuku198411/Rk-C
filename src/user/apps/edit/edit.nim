## Provides the edit command entry point and argument handling.
import ../../lib/core/io
import ../../lib/core/args
import ../../lib/core/app
import ../../lib/core/pathutils
import ../../lib/core/syscall
import ./internal/buffer
import ./internal/input


var
  parsedArgs: UserArgs


## Prints edit usage information.
proc printUsage() =
  write("usage: edit <path>\n")
  write("  save: C-x C-s\n")
  write("  exit: C-x C-c\n")
  write("  move: arrow keys\n")


## Parses the file path, loads content, and starts the editor.
proc user_start*(arg: cstring) {.exportc, cdecl, noreturn.} =
  parseArgsOrExit(arg, parsedArgs, printUsage)
  exitIfHelp(parsedArgs, printUsage)
  requireArgc(parsedArgs, U32(1), printUsage)

  let path = resolvePath(argAt(parsedArgs, 0))
  if path == nil:
    write("edit: path too long\n")
    sysExit(1)

  var len = load(path)
  editorLoop(path, len)
  sysExit(0)
