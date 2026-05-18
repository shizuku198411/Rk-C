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

    if cstringEq(cstr(cmdBuf), "help"):
      printHelp()

    elif cstringEq(cstr(cmdBuf), "cd"):
      changeDirectory(cstr(argBuf))

    elif cstringEq(cstr(cmdBuf), "ticks"):
      writeUnsigned(sysTicks())
      write("\n")

    elif cstringEq(cstr(cmdBuf), "traps"):
      printTrapCount()

    elif cstringEq(cstr(cmdBuf), "bitmap"):
      printBitmapInfo()

    elif cstringEq(cstr(cmdBuf), "history"):
      printHistory()

    elif cstringEq(cstr(cmdBuf), "exit"):
      if sysGetPpid() == 0:
        write("if you want to leave Rk-C, use \"shutdown\".\n")
        continue
      sysExit(0)
      

    elif cstringEq(cstr(cmdBuf), "shutdown"):
      saveHistory()
      if sysShutdown() != 0:
        write("failed to shutdown\n")

    else:
      runApp(buildBinPath(cstr(cmdBuf)), cstr(argBuf), background)
