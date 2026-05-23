## Implements the interactive shell command loop and built-in dispatch.
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


## Starts the shell loop, reads commands, and dispatches built-ins or apps.
proc user_start*(arg: cstring) {.exportc, cdecl, noreturn.} =
  discard arg

  if not initLineBuffer():
    write("shell: failed to allocate line buffer\n")
    sysExit(1)

  loadHistory()

  while true:
    printPrompt()
    let cmd = readLine()

    if cmd == nil:
      write("shell: failed to read line\n")
      continue

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

    elif cstringEq(cstr(cmdBuf), "su"):
      switchUser(cstr(argBuf))
    
    elif cstringEq(cstr(cmdBuf), "pwd"):
      printPwd()

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
      saveHistory()
      sysExit(0)

    elif cstringEq(cstr(cmdBuf), "shutdown"):
      kernelShutdown()

    else:
      runApp(buildBinPath(cstr(cmdBuf)), cstr(argBuf), background)
