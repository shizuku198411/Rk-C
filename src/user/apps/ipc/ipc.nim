## Sends or receives simple process-local IPC messages.
import ../../lib/core/io
import ../../lib/core/args
import ../../lib/core/app
import ../../lib/core/strutils
import ../../lib/core/syscall

const
  ArgMax = 160

var
  msg: SysIpcMessage
  parsedArgs: UserArgs
  messageBuf: array[ArgMax, char]


## Parses a decimal pid argument for IPC send.
proc parsePid(s: cstring, pid: var I32): bool =
  if s[0] < '0' or s[0] > '9':
    return false

  var value = I32(0)
  var pos = U32(0)
  while s[pos] >= '0' and s[pos] <= '9':
    value = value * 10 + I32(ord(s[pos]) - ord('0'))
    inc pos

  if s[pos] != '\0':
    return false

  pid = value
  true


## Prints ipc usage information.
proc printUsage() =
  write("usage:\n")
  write("  ipc send <pid> <message>\n")
  write("  ipc receive\n")


## Sends the requested message to the target pid.
proc sendMessage() =
  var pid = I32(0)
  if parsedArgs.argc < 3 or not parsePid(argAt(parsedArgs, 1), pid):
    printUsage()
    sysExit(1)

  if not copyArgvTail(parsedArgs, 2, addr messageBuf[0], U32(ArgMax)):
    printUsage()
    sysExit(1)

  if sysIpcSend(pid, cast[cstring](addr messageBuf[0])) != 0:
    write("ipc: send failed\n")
    sysExit(1)


## Receives one IPC message and prints sender and body.
proc receiveMessage() =
  if sysIpcReceive(addr msg) != 0:
    write("ipc: receive failed\n")
    sysExit(1)

  write("from ")
  writeUnsigned(U64(msg.senderPid))
  write(": ")
  write(cast[cstring](addr msg.data[0]))
  write("\n")


## Dispatches ipc send or receive mode.
proc user_start*(arg: cstring) {.exportc, cdecl, noreturn.} =
  discard ArgMax

  parseArgsOrExit(arg, parsedArgs, printUsage)
  exitIfHelp(parsedArgs, printUsage)
  requireMinArgc(parsedArgs, U32(1), printUsage)

  if cstringEq(argAt(parsedArgs, 0), "send"):
    sendMessage()
    sysExit(0)

  if cstringEq(argAt(parsedArgs, 0), "receive") and parsedArgs.argc == 1:
    receiveMessage()
    sysExit(0)

  printUsage()
  sysExit(1)
