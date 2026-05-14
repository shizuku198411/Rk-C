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
  services: array[ServiceCap, SysServiceInfo]
  restartPacket: SysIpcPacket
  parsedArgs: UserArgs


proc printUsage() =
  write("usage:\n")
  write("  svc list\n")
  write("  svc restart <service>\n")


proc printAvailable(value: U32) =
  if value != 0:
    write("yes")
  else:
    write("no")


proc printPaddedName(name: cstring) =
  var i = 0
  while i < ServiceNameWidth and name[i] != '\0':
    writeChar(name[i])
    inc i

  while i < ServiceNameWidth:
    write(" ")
    inc i


proc listServices() =
  let count = sysServiceList(addr services[0], U64(ServiceCap))
  if count < 0:
    write("svc: list failed\n")
    sysExit(1)

  printPaddedName("service")
  write("pid\tregistered\tavailable\n")

  var i = I32(0)
  while i < count:
    printPaddedName(cast[cstring](addr services[i].name[0]))
    writeUnsigned(U64(services[i].pid))
    write("\t")
    printAvailable(services[i].registered)
    write("\t\t")
    printAvailable(services[i].available)
    write("\n")
    inc i


proc managerPid(): I32 =
  servicePidByKind(SysServiceKindManager)


proc restartService() =
  if parsedArgs.argc != 2:
    printUsage()
    sysExit(1)

  let pid = managerPid()
  if pid <= 0:
    write("svc: manager unavailable\n")
    sysExit(1)

  restartPacket = SysIpcPacket()
  restartPacket.op = SysIpcOpSvcRestart

  let name = argAt(parsedArgs, 1)
  var i = U32(0)
  while i + 1 < U32(SysIpcMessageMax) and name[i] != '\0':
    restartPacket.data[int(i)] = name[i]
    inc i

  restartPacket.data[int(i)] = '\0'
  restartPacket.len = i

  if sendIpcRequest(pid, addr restartPacket) != 0:
    write("svc: restart request failed\n")
    sysExit(1)


proc user_start*(arg: cstring) {.exportc, cdecl, noreturn.} =
  if not parseUserArgs(arg, parsedArgs):
    printUsage()
    sysExit(1)

  if parsedArgs.argc == 1 and streq(argAt(parsedArgs, 0), "--help"):
    printUsage()
    sysExit(0)

  if parsedArgs.argc == 1 and streq(argAt(parsedArgs, 0), "list"):
    listServices()
    sysExit(0)

  if parsedArgs.argc >= 1 and streq(argAt(parsedArgs, 0), "restart"):
    restartService()
    sysExit(0)

  printUsage()
  sysExit(1)
