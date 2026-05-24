## Formats service-manager state and initializes service descriptors.

proc stateName(state: ServiceState): cstring =
  case state
  of srvStopped: cstring("stopped")
  of srvDegraded: cstring("degraded")
  of srvStarting: cstring("starting")
  of srvRunning: cstring("running")


proc appendChar(buf: ptr UncheckedArray[char], cap: U32, pos: var U32, ch: char) =
  if pos + U32(1) < cap:
    buf[pos] = ch
    inc pos
    buf[pos] = '\0'


proc appendStr(buf: ptr UncheckedArray[char], cap: U32, pos: var U32, s: cstring) =
  var i = U32(0)
  while s[i] != '\0':
    appendChar(buf, cap, pos, s[i])
    inc i


proc appendU64(buf: ptr UncheckedArray[char], cap: U32, pos: var U32, value: U64) =
  var
    tmp: array[32, char]
    n = value
    i = U32(0)

  if n == U64(0):
    appendChar(buf, cap, pos, '0')
    return

  while n > U64(0) and i < U32(32):
    tmp[i] = char(ord('0') + int(n mod U64(10)))
    n = n div U64(10)
    inc i

  while i > U32(0):
    dec i
    appendChar(buf, cap, pos, tmp[i])


proc appendI32(buf: ptr UncheckedArray[char], cap: U32, pos: var U32, value: I32) =
  if value < 0:
    appendChar(buf, cap, pos, '-')
    appendU64(buf, cap, pos, U64(-value))
  else:
    appendU64(buf, cap, pos, U64(value))


proc clearPacketData(packet: var SysIpcPacket) =
  var i = U32(0)
  while i < SysIpcMessageMax:
    packet.data[i] = '\0'
    inc i


proc logEvent(name, action: cstring) =
  let idx = serviceLogNext mod U32(ServiceLogCount)
  var pos = U32(0)
  let line = cast[ptr UncheckedArray[char]](addr serviceLogs[idx][0])

  var i = U32(0)
  while i < U32(ServiceLogLen):
    line[i] = '\0'
    inc i

  appendStr(line, U32(ServiceLogLen), pos, cstring("["))
  appendU64(line, U32(ServiceLogLen), pos, sysTicks())
  appendStr(line, U32(ServiceLogLen), pos, cstring("] "))
  appendStr(line, U32(ServiceLogLen), pos, name)
  appendStr(line, U32(ServiceLogLen), pos, cstring(" "))
  appendStr(line, U32(ServiceLogLen), pos, action)

  serviceLogNext = (serviceLogNext + U32(1)) mod U32(ServiceLogCount)
  if serviceLogTotal < U32(ServiceLogCount):
    inc serviceLogTotal


proc initServices() =
  var i = 0
  while i < len(services):
    services[i].kind = managedServices[i].kind
    services[i].name = managedServices[i].name
    services[i].path = managedServices[i].path
    services[i].required = managedServices[i].required
    services[i].pid = -1
    services[i].state = srvStopped
    services[i].startCount = 0
    services[i].restarts = 0
    services[i].readyDeadline = 0
    services[i].lastReadyTick = 0
    services[i].lastExitStatus = 0
    services[i].lastFailureReason = cstring("none")
    services[i].livenessMisses = U32(0)
    inc i


