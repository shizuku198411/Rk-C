## Parses shell command lines and runs apps with pipes, redirection, or bg mode.
import ../../lib/core/io
import ../../lib/core/strutils
import ../../lib/core/pathutils
import ../../lib/core/syscall
import ../../../lib/service_catalog
import ./state


## Clears a line-sized shell buffer.
proc clearBuffer(buf: ptr UncheckedArray[char]) =
  clearCommandScratchBuffer(buf)


## Advances a parser cursor over ASCII spaces.
proc skipSpaces(s: cstring, pos: var int) =
  while s[pos] == ' ':
    inc pos


## Splits a command line into command and raw argument buffers.
proc parseCommandInto(line: cstring, cmd, arg: ptr UncheckedArray[char]): bool =
  if line == nil or cmd == nil or arg == nil:
    return false

  clearBuffer(cmd)
  clearBuffer(arg)

  var pos = 0
  skipSpaces(line, pos)

  var i = U64(0)
  while line[pos] != '\0' and line[pos] != ' ' and i < CommandScratchBufferCap - 1:
    cmd[i] = line[pos]
    inc i
    inc pos
  cmd[i] = '\0'
  if i == 0:
    return false

  skipSpaces(line, pos)
  i = 0
  while line[pos] != '\0' and i < CommandScratchBufferCap - 1:
    arg[i] = line[pos]
    inc i
    inc pos
  arg[i] = '\0'
  true


## Parses the active shell line into the shared command and argument buffers.
proc parseCommand*(line: cstring): bool =
  if line == nil:
    return false

  if cmdBuf == nil or argBuf == nil:
    return false

  clearCmdBuffer()
  clearArgBuffer()

  var i = 0

  while line[i] == ' ':
    inc i

  if line[i] == '\0':
    return false

  var cmdPos = 0
  while line[i] != '\0' and line[i] != ' ':
    if cmdPos + 1 < cmdBufCap:
      cmdBuf[cmdPos] = line[i]
      inc cmdPos
    inc i

  cmdBuf[cmdPos] = '\0'

  if cmdPos == 0:
    return false

  while line[i] == ' ':
    inc i

  var argPos = 0
  while line[i] != '\0':
    if argPos + 1 < argBufCap:
      argBuf[argPos] = line[i]
      inc argPos
    inc i

  argBuf[argPos] = '\0'

  true


## Builds a /bin/<command> executable path into the requested buffer.
proc buildBinPathInto(cmd: cstring, dst: ptr UncheckedArray[char]): cstring =
  if cmd == nil or dst == nil:
    return nil

  clearBuffer(dst)
  dst[0] = '/'
  dst[1] = 'b'
  dst[2] = 'i'
  dst[3] = 'n'
  dst[4] = '/'
  var i = U64(0)
  while cmd[i] != '\0' and i + 5 < CommandScratchBufferCap - 1:
    dst[i + 5] = cmd[i]
    inc i

  if cmd[i] != '\0':
    return nil

  dst[i + 5] = '\0'
  cast[cstring](addr dst[0])


## Builds a /bin/<command> executable path into the shared path buffer.
proc buildBinPath*(cmd: cstring): cstring =
  if cmd == nil:
    return nil

  if not initPathBuffer():
    return nil

  clearPathBuffer()

  var pos = 0

  if cmd[0] == '/':
    while cmd[pos] != '\0' and pos + 1 < pathBufCap:
      pathBuf[pos] = cmd[pos]
      inc pos

    if cmd[pos] != '\0':
      return nil

    pathBuf[pos] = '\0'
    return pathCString()

  let prefix = cstring"/bin/"
  var i = 0

  while prefix[i] != '\0' and pos + 1 < pathBufCap:
    pathBuf[pos] = prefix[i]
    inc pos
    inc i

  i = 0
  while cmd[i] != '\0' and pos + 1 < pathBufCap:
    pathBuf[pos] = cmd[i]
    inc pos
    inc i

  if cmd[i] != '\0':
    return nil

  pathBuf[pos] = '\0'
  pathCString()


## Removes a trailing background marker from an argument buffer.
proc stripBackgroundMarkerFrom(buf: ptr UncheckedArray[char]): bool =
  if buf == nil:
    return false

  var len = U64(0)
  while len < CommandScratchBufferCap and buf[len] != '\0':
    inc len

  while len > 0 and buf[len - 1] == ' ':
    dec len
    buf[len] = '\0'

  if len == 0 or buf[len - 1] != '&':
    return false

  dec len
  buf[len] = '\0'
  while len > 0 and buf[len - 1] == ' ':
    dec len
    buf[len] = '\0'

  true


proc buildBinPathIntoHeap*(
  cmd: cstring,
  outBuf: ptr UncheckedArray[char],
  outCap: int
): cstring =
  if outBuf == nil or outCap <= 0:
    return nil

  var i = 0
  while i < outCap:
    outBuf[i] = '\0'
    inc i

  if cmd == nil:
    return cast[cstring](addr outBuf[0])

  var pos = 0

  if cmd[0] == '/':
    i = 0
    while cmd[i] != '\0' and pos + 1 < outCap:
      outBuf[pos] = cmd[i]
      inc pos
      inc i

    if cmd[i] != '\0':
      return nil

    outBuf[pos] = '\0'
    return cast[cstring](addr outBuf[0])

  let prefix = cstring"/bin/"
  i = 0
  while prefix[i] != '\0' and pos + 1 < outCap:
    outBuf[pos] = prefix[i]
    inc pos
    inc i

  i = 0
  while cmd[i] != '\0' and pos + 1 < outCap:
    outBuf[pos] = cmd[i]
    inc pos
    inc i

  if cmd[i] != '\0':
    return nil

  outBuf[pos] = '\0'
  cast[cstring](addr outBuf[0])


## Copies a command line into the pipeline scratch buffer.
proc copyPipelineLine(line: cstring) =
  if pipelineLineBuf == nil:
    return

  clearBuffer(pipelineLineBuf)
  var i = U64(0)
  while line[i] != '\0' and i < CommandScratchBufferCap - 1:
    pipelineLineBuf[i] = line[i]
    inc i
  pipelineLineBuf[i] = '\0'


## Splits a single-pipe command line into left and right command lines.
proc splitPipeline(line: cstring): bool =
  if line == nil or leftLineBuf == nil or rightLineBuf == nil:
    return false

  clearBuffer(leftLineBuf)
  clearBuffer(rightLineBuf)

  var pipePos = -1
  var pos = 0
  while line[pos] != '\0':
    if line[pos] == '|':
      if pipePos >= 0:
        write("pipe: only one pipe is supported\n")
        return false
      pipePos = pos
    inc pos

  if pipePos < 0:
    return false

  var i = U64(0)
  while int(i) < pipePos and i < CommandScratchBufferCap - 1:
    leftLineBuf[i] = line[i]
    inc i
  leftLineBuf[i] = '\0'

  i = 0
  pos = pipePos + 1
  while line[pos] != '\0' and i < CommandScratchBufferCap - 1:
    rightLineBuf[i] = line[pos]
    inc i
    inc pos
  rightLineBuf[i] = '\0'
  true


## Copies a command line into the redirection scratch buffer.
proc copyRedirectLine(line: cstring) =
  if redirectLineBuf == nil:
    return

  clearBuffer(redirectLineBuf)
  var i = U64(0)
  while line[i] != '\0' and i < CommandScratchBufferCap - 1:
    redirectLineBuf[i] = line[i]
    inc i
  redirectLineBuf[i] = '\0'


## Returns whether a command line contains a specific character.
proc containsChar(line: cstring, ch: char): bool =
  var i = 0
  while line[i] != '\0':
    if line[i] == ch:
      return true
    inc i

  false


## Copies and trims a substring from one command line into a buffer.
proc copyTrimmedRange(src: cstring, startPos, endPos: int,
                      dst: ptr UncheckedArray[char]) =
  if src == nil or dst == nil:
    return

  clearBuffer(dst)

  var start = startPos
  var finish = endPos
  while start < finish and src[start] == ' ':
    inc start
  while finish > start and src[finish - 1] == ' ':
    dec finish

  var i = U64(0)
  var pos = start
  while pos < finish and i < CommandScratchBufferCap - 1:
    dst[i] = src[pos]
    inc i
    inc pos
  dst[i] = '\0'


## Splits a stdout redirection command line into command and target path.
proc splitRedirection(line: cstring): bool =
  if line == nil or leftLineBuf == nil or redirectTargetBuf == nil:
    return false

  clearBuffer(leftLineBuf)
  clearBuffer(redirectTargetBuf)

  var redirectPos = -1
  var pos = 0
  while line[pos] != '\0':
    if line[pos] == '>':
      if redirectPos >= 0:
        write("redirect: only one > is supported\n")
        return false
      redirectPos = pos
    inc pos

  if redirectPos < 0:
    return false

  copyTrimmedRange(line, 0, redirectPos, leftLineBuf)
  copyTrimmedRange(line, redirectPos + 1, pos, redirectTargetBuf)
  true


## Restores a saved file descriptor onto a target descriptor and closes it.
proc restoreFd(savedFd, targetFd: I32) =
  if savedFd >= 0:
    discard sysDup2(savedFd, targetFd)
    discard sysClose(savedFd)


## Reports a generic command lookup failure.
proc reportExecFailure(path: cstring) =
  write("command not found: ")
  write(path)
  write("\n")


## Reports that a command executable path exceeded the shell path capacity.
proc reportCommandPathTooLong() =
  write("command path too long\n")


## check if the app execution is alloed or not
proc isAllowedPath(path: cstring): bool =
  # deny login app
  if cstringEq(path, "/bin/login"):
    return false

  # deny services run from shell
  if cstringEq(path, "/bin/svcmgtd"):
    return false
  var i = 0
  while i < managedServices.len:
    if cstringEq(path, managedServices[i].path):
      return false
    inc i
  
  true


## Reports an exec failure using kernel-specific exec return codes.
proc reportExecFailure(path: cstring, rc: I32) =
  if rc == SysExecNoProcess:
    write("exec: process table full\n")
    return
  if rc == SysExecPermission:
    write("permission denied: ")
    write(path)
    write("\n")
    return
  if rc == SysExecNoEntry:
    reportExecFailure(path)
    return

  reportExecFailure(path)


## Runs a command with stdout redirected to a file.
proc runRedirection*(line: cstring): bool =
  copyRedirectLine(line)
  let background = stripBackgroundMarkerFrom(redirectLineBuf)

  if not splitRedirection(cstr(redirectLineBuf)):
    return false

  if containsChar(cstr(leftLineBuf), '|') or containsChar(cstr(redirectTargetBuf), '|'):
    write("redirect: pipe with redirection is not supported yet\n")
    return true

  if redirectTargetBuf[0] == '\0' or
      not parseCommandInto(cstr(leftLineBuf), leftCmdBuf, leftArgBuf):
    write("usage: <command> > <path>\n")
    return true

  let targetPath = resolvePath(cstr(redirectTargetBuf))
  if targetPath == nil:
    write("redirect: path too long\n")
    return true

  let outFd = sysOpen(targetPath, SysOpenWrite or SysOpenCreate or SysOpenTrunc)
  if outFd < 0:
    write("redirect: failed to open ")
    write(targetPath)
    write("\n")
    return true

  let savedStdout = sysOpen("/dev/stdout", SysOpenWrite)
  if savedStdout < 0:
    discard sysClose(outFd)
    write("redirect: failed to save stdout\n")
    return true

  if sysDup2(outFd, 1) < 0:
    restoreFd(savedStdout, 1)
    discard sysClose(outFd)
    write("redirect: failed to redirect stdout\n")
    return true

  discard sysClose(outFd)

  let execPath = buildBinPathInto(cstr(leftCmdBuf), leftPathBuf)
  if execPath == nil:
    restoreFd(savedStdout, 1)
    reportCommandPathTooLong()
    return true

  if not isAllowedPath(execPath):
    restoreFd(savedStdout, 1)
    write("cannnot execute ")
    write(execPath)
    write(" directly from shell.\n")
    return true

  let pid = sysExec(execPath, cstr(leftArgBuf), background)
  restoreFd(savedStdout, 1)
  if pid < 0:
    reportExecFailure(cstr(leftPathBuf), pid)
    return true

  if background:
    write("[bg] pid ")
    writeUnsigned(U64(pid))
    write("\n")
    return true

  discard sysWait(pid)
  true


## Runs a two-command pipeline by wiring stdout of the left app to stdin.
proc runPipeline*(line: cstring): bool =
  copyPipelineLine(line)
  let background = stripBackgroundMarkerFrom(pipelineLineBuf)

  if not splitPipeline(cstr(pipelineLineBuf)):
    return false

  if not parseCommandInto(cstr(leftLineBuf), leftCmdBuf, leftArgBuf) or
      not parseCommandInto(cstr(rightLineBuf), rightCmdBuf, rightArgBuf):
    write("usage: <command> | <command>\n")
    return true

  var fds: array[2, I32]
  if sysPipe(addr fds[0]) != 0:
    write("pipe: failed\n")
    return true

  let savedStdout = sysOpen("/dev/stdout", SysOpenWrite)
  if savedStdout < 0:
    discard sysClose(fds[0])
    discard sysClose(fds[1])
    write("pipe: failed to save stdout\n")
    return true

  if sysDup2(fds[1], 1) < 0:
    restoreFd(savedStdout, 1)
    discard sysClose(fds[0])
    discard sysClose(fds[1])
    write("pipe: failed to redirect stdout\n")
    return true

  discard sysClose(fds[1])

  let execPath = buildBinPathInto(cstr(leftCmdBuf), leftPathBuf)
  if execPath == nil:
    restoreFd(savedStdout, 1)
    discard sysClose(fds[0])
    reportCommandPathTooLong()
    return true

  if not isAllowedPath(execPath):
    restoreFd(savedStdout, 1)
    discard sysClose(fds[0])
    write("cannnot execute ")
    write(execPath)
    write(" directly from shell.\n")
    return true

  let leftPid = sysExec(execPath, cstr(leftArgBuf), background)
  restoreFd(savedStdout, 1)
  if leftPid < 0:
    discard sysClose(fds[0])
    reportExecFailure(cstr(leftPathBuf), leftPid)
    return true

  let savedStdin = sysOpen("/dev/stdin", SysOpenRead)
  if savedStdin < 0:
    discard sysClose(fds[0])
    discard sysWait(leftPid)
    write("pipe: failed to save stdin\n")
    return true

  if sysDup2(fds[0], 0) < 0:
    restoreFd(savedStdin, 0)
    discard sysClose(fds[0])
    discard sysWait(leftPid)
    write("pipe: failed to redirect stdin\n")
    return true

  discard sysClose(fds[0])

  let rightExecPath = buildBinPathInto(cstr(rightCmdBuf), rightPathBuf)
  if rightExecPath == nil:
    restoreFd(savedStdin, 0)
    discard sysWait(leftPid)
    reportCommandPathTooLong()
    return true

  if not isAllowedPath(rightExecPath):
    restoreFd(savedStdin, 0)
    discard sysWait(leftPid)
    write("cannnot execute ")
    write(rightExecPath)
    write(" directly from shell.\n")
    return true

  let rightPid = sysExec(rightExecPath, cstr(rightArgBuf), background)
  restoreFd(savedStdin, 0)
  if rightPid < 0:
    discard sysWait(leftPid)
    reportExecFailure(cstr(rightPathBuf), rightPid)
    return true

  if background:
    write("[bg] pid ")
    writeUnsigned(U64(leftPid))
    write(" | pid ")
    writeUnsigned(U64(rightPid))
    write("\n")
    return true

  discard sysWait(leftPid)
  discard sysWait(rightPid)
  true


## Starts an app and optionally waits for it to finish.
proc runApp*(path: cstring, arg: cstring, background: bool) =
  if not isAllowedPath(path):
    write("cannnot execute ")
    write(path)
    write(" directly from shell.\n")
    return

  let pid = sysExec(path, arg, background)
  if pid < 0:
    reportExecFailure(path, pid)
    return

  if background:
    write("[bg] pid ")
    writeUnsigned(U64(pid))
    write("\n")
    return

  discard sysWait(pid)


## Removes a trailing background marker from the shared argument buffer.
proc stripBackgroundMarker*(): bool =
  if argBuf == nil:
    return false

  var len = 0

  while len < argBufCap and argBuf[len] != '\0':
    inc len

  while len > 0 and argBuf[len - 1] == ' ':
    dec len
    argBuf[len] = '\0'

  if len > 0 and argBuf[len - 1] == '&':
    dec len
    argBuf[len] = '\0'

    while len > 0 and argBuf[len - 1] == ' ':
      dec len
      argBuf[len] = '\0'

    return true

  false
