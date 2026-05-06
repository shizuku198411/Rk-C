import ../../lib/io
import ../../lib/strutils
import ../../lib/syscall

const
  ServiceCap = 8

var
  services: array[ServiceCap, SysServiceInfo]
  restartPacket: SysIpcPacket


proc startsWithWord(s, word: cstring): bool =
  var i = 0
  while word[i] != '\0':
    if s[i] != word[i]:
      return false
    inc i

  s[i] == '\0' or s[i] == ' '


proc skipSpaces(s: cstring, pos: var int) =
  while s[pos] == ' ':
    inc pos


proc printUsage() =
  write("usage:\n")
  write("  svc list\n")
  write("  svc restart <service>\n")


proc printAvailable(value: U32) =
  if value != 0:
    write("yes")
  else:
    write("no")


proc listServices() =
  let count = sysServiceList(addr services[0], U64(ServiceCap))
  if count < 0:
    write("svc: list failed\n")
    sysExit(1)

  write("service\tpid\tregistered\tavailable\n")

  var i = I32(0)
  while i < count:
    write(cast[cstring](addr services[i].name[0]))
    write("\t")
    writeUnsigned(U64(services[i].pid))
    write("\t")
    printAvailable(services[i].registered)
    write("\t\t")
    printAvailable(services[i].available)
    write("\n")
    inc i


proc managerPid(): I32 =
  let count = sysServiceList(addr services[0], U64(ServiceCap))
  if count < 0:
    return -1

  var i = I32(0)
  while i < count:
    if services[i].kind == SysServiceKindManager and services[i].available != 0:
      return services[i].pid
    inc i

  -1


proc restartService(arg: cstring) =
  var pos = 7
  skipSpaces(arg, pos)
  if arg[pos] == '\0':
    printUsage()
    sysExit(1)

  let pid = managerPid()
  if pid <= 0:
    write("svc: manager unavailable\n")
    sysExit(1)

  restartPacket = SysIpcPacket()
  restartPacket.op = SysIpcOpSvcRestart

  var i = U32(0)
  while i + 1 < U32(SysIpcMessageMax) and arg[pos + int(i)] != '\0':
    restartPacket.data[int(i)] = arg[pos + int(i)]
    inc i

  restartPacket.data[int(i)] = '\0'
  restartPacket.len = i

  if sysIpcSendPacket(pid, addr restartPacket) != 0:
    write("svc: restart request failed\n")
    sysExit(1)


proc user_start*(arg: cstring) {.exportc, cdecl, noreturn.} =
  if isEmpty(arg):
    printUsage()
    sysExit(1)

  if startsWithWord(arg, "list"):
    listServices()
    sysExit(0)

  if startsWithWord(arg, "restart"):
    restartService(arg)
    sysExit(0)

  printUsage()
  sysExit(1)
