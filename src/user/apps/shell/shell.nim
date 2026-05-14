import ../../lib/core/io
import ../../lib/core/strutils
import ../../lib/core/syscall
import ./builtins
import ./command
import ./help
import ./history
import ./line_editor
import ./prompt
import ./state


proc user_start*(arg: cstring) {.exportc, cdecl, noreturn.} =
  discard arg

  loadHistory()

  while true:
    printPrompt()
    let cmd = readLine()

    if runRedirection(cmd):
      storeHistory()
      continue

    if runPipeline(cmd):
      storeHistory()
      continue

    if not parseCommand(cmd):
      continue

    storeHistory()

    let background = stripBackgroundMarker()

    if streq(cstr(cmdBuf), "help"):
      printHelp()

    elif streq(cstr(cmdBuf), "cd"):
      changeDirectory(cstr(argBuf))

    elif streq(cstr(cmdBuf), "ticks"):
      writeUnsigned(sysTicks())
      write("\n")

    elif streq(cstr(cmdBuf), "traps"):
      printTrapCount()

    elif streq(cstr(cmdBuf), "bitmap"):
      printBitmapInfo()

    elif streq(cstr(cmdBuf), "history"):
      printHistory()

    elif streq(cstr(cmdBuf), "exit"):
      sysExit(0)

    elif streq(cstr(cmdBuf), "shutdown"):
      saveHistory()
      sysShutdown()

    else:
      runApp(buildBinPath(cstr(cmdBuf)), cstr(argBuf), background)
