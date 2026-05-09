import ../../lib/core/io
import ../../lib/core/strutils
import ../../lib/core/syscall

const
  ArgMax = 160

var msg: SysIpcMessage


proc skipSpaces(s: cstring, pos: var int) =
  while s[pos] == ' ':
    inc pos


proc parsePid(s: cstring, pos: var int, pid: var I32): bool =
  skipSpaces(s, pos)
  if s[pos] < '0' or s[pos] > '9':
    return false

  var value = I32(0)
  while s[pos] >= '0' and s[pos] <= '9':
    value = value * 10 + I32(ord(s[pos]) - ord('0'))
    inc pos

  pid = value
  true


proc startsWithWord(s, word: cstring): bool =
  var i = 0
  while word[i] != '\0':
    if s[i] != word[i]:
      return false
    inc i

  s[i] == '\0' or s[i] == ' '


proc printUsage() =
  write("usage:\n")
  write("  ipc send <pid> <message>\n")
  write("  ipc receive\n")


proc sendMessage(arg: cstring) =
  var pos = 4
  var pid = I32(0)
  if not parsePid(arg, pos, pid):
    printUsage()
    sysExit(1)

  skipSpaces(arg, pos)
  if arg[pos] == '\0':
    printUsage()
    sysExit(1)

  if sysIpcSend(pid, cast[cstring](unsafeAddr arg[pos])) != 0:
    write("ipc: send failed\n")
    sysExit(1)


proc receiveMessage() =
  if sysIpcReceive(addr msg) != 0:
    write("ipc: receive failed\n")
    sysExit(1)

  write("from ")
  writeUnsigned(U64(msg.senderPid))
  write(": ")
  write(cast[cstring](addr msg.data[0]))
  write("\n")


proc user_start*(arg: cstring) {.exportc, cdecl, noreturn.} =
  discard ArgMax

  if isEmpty(arg):
    printUsage()
    sysExit(1)

  if startsWithWord(arg, "send"):
    sendMessage(arg)
    sysExit(0)

  if startsWithWord(arg, "receive"):
    receiveMessage()
    sysExit(0)

  printUsage()
  sysExit(1)
