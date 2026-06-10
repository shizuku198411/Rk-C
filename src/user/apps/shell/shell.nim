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


proc allocateBuffers() =
  if not initLineBuffer():
    write("shell: failed to allocate line buffer\n")
    sysExit(1)

  if not initCmdBuffer():
    write("shell: failed to allocate command buffer\n")
    sysExit(1)

  if not initArgBuffer():
    write("shell: failed to allocate argument buffer\n")
    sysExit(1)

  if not initPathBuffer():
    write("shell: failed to allocate path buffer\n")
    sysExit(1)

  if not initCommandScratchBuffers():
    write("shell: failed to allocate command scratch buffers\n")
    sysExit(1)

  if not initHistorySaveBuffer():
    write("shell: failed to allocate history buffer\n")
    sysExit(1)

  if not initHistoryPathBuffer():
    write("shell: failed to allocate history path buffer\n")
    sysExit(1)


## Starts the shell loop, reads commands, and dispatches built-ins or apps.
proc user_start*(arg: cstring) {.exportc, cdecl, noreturn.} =
  discard arg

  allocateBuffers()

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

    if cstringEq(cmdCString(), "help"):
      printHelp()

    elif setEnvironmentAssignment(cmdCString(), argCString()):
      discard

    elif cstringEq(cmdCString(), "cd"):
      changeDirectory(argCString())

    elif cstringEq(cmdCString(), "su"):
      switchUser(argCString())

    elif cstringEq(cmdCString(), "pwd"):
      printPwd()

    elif cstringEq(cmdCString(), "ticks"):
      writeUnsigned(sysTicks())
      write("\n")

    elif cstringEq(cmdCString(), "traps"):
      printTrapCount()

    elif cstringEq(cmdCString(), "bitmap"):
      printBitmapInfo()

    elif cstringEq(cmdCString(), "history"):
      printHistory()

    elif cstringEq(cmdCString(), "exit"):
      saveHistory()
      sysExit(0)

    else:
      if cstringEq(cmdCString(), "sudo"):
        saveHistory()

      let path = resolveExecPath(cmdCString(), pathBuf, pathBufCap)
      if path != nil:
        runApp(path, copyArgToExecArgBuffer(), background)
