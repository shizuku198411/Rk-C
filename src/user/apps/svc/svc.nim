## Controls and inspects supervised services through svcmgtd.
{.warning[UnusedImport]: off.}

import ../../lib/runtime/orc_osalloc
import ../../lib/core/io
import ../../lib/ipc/ipc_request
import ../../lib/ipc/service_client
import ../../lib/core/args
import ../../lib/core/strutils
import ../../lib/core/syscall

const
  ServiceCap = 8
  ServiceNameWidth = 12

var
  services: seq[SysServiceInfo] = @[]
  renderedText: string = ""
  requestPacket: SysIpcPacket
  responsePacket: SysIpcPacket
  parsedArgs: UserArgs


## Allocates the ORC-managed service list workspace when list output is requested.
proc initServiceStorage() =
  services = newSeq[SysServiceInfo](ServiceCap)


## Clears the ORC-managed output builder for one list result.
proc clearRenderedText() =
  renderedText = ""


## Appends one character to the ORC-managed output builder.
proc appendChar(ch: char) =
  renderedText.add(ch)


## Appends one C string to the ORC-managed output builder.
proc appendText(text: cstring) =
  if text == nil:
    return

  var i = 0
  while text[i] != '\0':
    appendChar(text[i])
    inc i


## Appends a C string followed by spaces until the fixed column width is met.
proc appendPaddedText(text: cstring, width: int) =
  var i = 0
  while i < width and text != nil and text[i] != '\0':
    appendChar(text[i])
    inc i

  while i < width:
    appendChar(' ')
    inc i


## Appends one unsigned decimal integer to the ORC-managed output builder.
proc appendUnsigned(value: U64) =
  var
    tmp: array[32, char]
    n = value
    len = 0

  if n == U64(0):
    appendChar('0')
    return

  while n > U64(0) and len < 32:
    tmp[len] = char(ord('0') + int(n mod U64(10)))
    n = n div U64(10)
    inc len

  while len > 0:
    dec len
    appendChar(tmp[len])


## Appends a yes/no display value to the ORC-managed output builder.
proc appendYesNo(value: U32) =
  if value != U32(0):
    appendText(cstring("yes"))
  else:
    appendText(cstring("no"))


## Flushes the ORC-managed output builder to stdout.
proc flushRenderedText() =
  if renderedText.len > 0:
    discard sysWriteFd(1, addr renderedText[0], U64(renderedText.len))


## Prints svc usage information.
proc printUsage() =
  write("usage:\n")
  write("  svc list\n")
  write("  svc status [service]\n")
  write("  svc degraded\n")
  write("  svc logs\n")
  write("  svc start <service>\n")
  write("  svc stop <service>\n")
  write("  svc restart <service>\n")


## Lists registered services directly from the kernel service registry.
proc listServices() =
  initServiceStorage()

  let count = sysServiceList(addr services[0], U64(ServiceCap))
  if count < 0:
    write("svc: list failed\n")
    sysExit(1)

  clearRenderedText()
  appendPaddedText(cstring("service"), ServiceNameWidth)
  appendText(cstring("pid\tregistered\tavailable\n"))

  var i = I32(0)
  while i < count:
    appendPaddedText(cast[cstring](addr services[i].name[0]), ServiceNameWidth)
    appendUnsigned(U64(services[i].pid))
    appendChar('\t')
    appendYesNo(services[i].registered)
    appendText(cstring("\t\t"))
    appendYesNo(services[i].available)
    appendChar('\n')
    inc i

  flushRenderedText()


## Returns the service manager pid.
proc managerPid(): I32 =
  servicePidByKind(SysServiceKindManager)


## Copies a service name argument into the request packet payload.
proc copyNameToPacket(name: cstring) =
  var i = U32(0)
  while i + 1 < U32(SysIpcMessageMax) and name != nil and name[i] != '\0':
    requestPacket.data[int(i)] = name[i]
    inc i

  requestPacket.data[int(i)] = '\0'
  requestPacket.len = i


## Sends a command request to svcmgtd and prints any textual response.
proc requestManager(op, expectedOp: U32, name: cstring = nil, arg0: U64 = U64(0)) =
  let pid = managerPid()
  if pid <= 0:
    write("svc: manager unavailable\n")
    sysExit(1)

  requestPacket = SysIpcPacket()
  requestPacket.op = op
  requestPacket.arg0 = arg0
  copyNameToPacket(name)

  if requestIpcReply(pid, addr requestPacket, addr responsePacket, expectedOp) != 0:
    write("svc: request failed\n")
    sysExit(1)

  if responsePacket.len > 0:
    discard sysWriteFd(1, addr responsePacket.data[0], U64(responsePacket.len))

  if responsePacket.arg0 != U64(0):
    sysExit(1)


## Requests a service restart.
proc restartService() =
  if parsedArgs.argc != 2:
    printUsage()
    sysExit(1)

  requestManager(SysIpcOpSvcRestart, SysIpcOpSvcCommandResponse, argAt(parsedArgs, 1))


## Requests a service start.
proc startService() =
  if parsedArgs.argc != 2:
    printUsage()
    sysExit(1)

  requestManager(SysIpcOpSvcStart, SysIpcOpSvcCommandResponse, argAt(parsedArgs, 1))


## Requests a service stop.
proc stopService() =
  if parsedArgs.argc != 2:
    printUsage()
    sysExit(1)

  requestManager(SysIpcOpSvcStop, SysIpcOpSvcCommandResponse, argAt(parsedArgs, 1))


## Requests service status, optionally for one service.
proc statusServices() =
  if parsedArgs.argc > 2:
    printUsage()
    sysExit(1)

  let name =
    if parsedArgs.argc == 2:
      argAt(parsedArgs, 1)
    else:
      nil

  requestManager(SysIpcOpSvcStatusRequest, SysIpcOpSvcStatusResponse, name)


## Requests only degraded service status from svcmgtd.
proc degradedServices() =
  if parsedArgs.argc != 1:
    printUsage()
    sysExit(1)

  requestManager(SysIpcOpSvcStatusRequest, SysIpcOpSvcStatusResponse, nil, U64(1))


## Requests service manager log output.
proc serviceLogs() =
  if parsedArgs.argc != 1:
    printUsage()
    sysExit(1)

  requestManager(SysIpcOpSvcLogsRequest, SysIpcOpSvcLogsResponse)


## Dispatches svc subcommands.
proc user_start*(arg: cstring) {.exportc, cdecl, noreturn.} =
  if not parseUserArgs(arg, parsedArgs):
    printUsage()
    sysExit(1)

  if parsedArgs.argc == 1 and cstringEq(argAt(parsedArgs, 0), "--help"):
    printUsage()
    sysExit(0)

  if parsedArgs.argc == 1 and cstringEq(argAt(parsedArgs, 0), "list"):
    listServices()
    sysExit(0)

  if parsedArgs.argc >= 1 and cstringEq(argAt(parsedArgs, 0), "restart"):
    restartService()
    sysExit(0)

  if parsedArgs.argc >= 1 and cstringEq(argAt(parsedArgs, 0), "start"):
    startService()
    sysExit(0)

  if parsedArgs.argc >= 1 and cstringEq(argAt(parsedArgs, 0), "stop"):
    stopService()
    sysExit(0)

  if parsedArgs.argc >= 1 and cstringEq(argAt(parsedArgs, 0), "status"):
    statusServices()
    sysExit(0)

  if parsedArgs.argc >= 1 and cstringEq(argAt(parsedArgs, 0), "degraded"):
    degradedServices()
    sysExit(0)

  if parsedArgs.argc >= 1 and cstringEq(argAt(parsedArgs, 0), "logs"):
    serviceLogs()
    sysExit(0)

  printUsage()
  sysExit(1)
