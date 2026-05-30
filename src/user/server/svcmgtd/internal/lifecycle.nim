## Tracks service health and controls process start, stop, and restart.

proc processState(pid: I32, state: var U32): bool =
  let count = sysPs(addr processes[0], U64(ProcessCap), SysProcListAllSlots)
  if count < 0:
    return false

  var i = I32(0)
  while i < count:
    if processes[i].pid == pid:
      state = processes[i].state
      return true
    inc i

  false


## Refreshes the kernel service registry snapshot once for one monitor pass.
proc refreshServiceSnapshot(): bool =
  kernelServiceCount = sysServiceList(addr kernelServices[0], U64(SysServiceRegistryCount))
  if kernelServiceCount < 0:
    kernelServiceCount = -1
    return false

  true


## Returns whether the cached kernel registry still marks this service alive.
proc serviceAliveInSnapshot(entry: ptr ServiceEntry): bool =
  if entry == nil or entry.pid <= 0 or kernelServiceCount < 0:
    return false

  var i = I32(0)
  while i < kernelServiceCount:
    if kernelServices[i].kind == entry.kind and kernelServices[i].pid == entry.pid:
      return kernelServices[i].available != U32(0)
    inc i

  false


## Returns whether the service process is alive using the cheapest source.
proc serviceAlive(entry: ptr ServiceEntry): bool =
  if entry == nil or entry.pid <= 0:
    return false

  if entry.state == srvRunning:
    return serviceAliveInSnapshot(entry)

  var state = U32(0)
  if not processState(entry.pid, state):
    return false

  state != SysProcessZombie and state != SysProcessUnused


proc unregisterService(entry: ptr ServiceEntry) =
  discard sysServiceUnregister(entry.kind)
  entry.state = srvStopped


proc stopService(entry: ptr ServiceEntry, reason: cstring = cstring("manual_stop")) =
  unregisterService(entry)
  if entry.pid <= 0:
    entry.lastFailureReason = reason
    return

  if serviceAlive(entry):
    discard sysKill(entry.pid)

  entry.lastExitStatus = sysWait(entry.pid)
  entry.pid = -1
  entry.state = srvStopped
  entry.lastFailureReason = reason
  logEvent(entry.name, reason)


proc degradeService(entry: ptr ServiceEntry, reason: cstring = cstring("degraded")) =
  unregisterService(entry)
  if entry.pid > 0:
    if serviceAlive(entry):
      discard sysKill(entry.pid)
    entry.lastExitStatus = sysWait(entry.pid)
  entry.pid = -1
  entry.state = srvDegraded
  entry.lastFailureReason = reason
  logEvent(entry.name, reason)
  write("[svcmgtd] service degraded ")
  write(entry.name)
  write("\n")


proc findServiceByPid(pid: I32): ptr ServiceEntry =
  var i = 0
  while i < len(services):
    if services[i].pid == pid:
      return addr services[i]
    inc i

  nil


proc markServiceReady(entry: ptr ServiceEntry) =
  if entry == nil or entry.pid <= 0:
    return

  if sysServiceReady(entry.kind, entry.pid) != 0:
    write("[svcmgtd] failed to mark ready ")
    write(entry.name)
    write("\n")
    return

  entry.state = srvRunning
  entry.lastReadyTick = sysTicks()
  entry.lastFailureReason = cstring("none")
  entry.livenessMisses = U32(0)
  logEvent(entry.name, cstring("ready"))
  write("[svcmgtd] service ready ")
  write(entry.name)
  write(" pid=")
  writeUnsigned(U64(entry.pid))
  write("\n")


proc startService(entry: ptr ServiceEntry) =
  inc entry.startCount
  let pid = sysExec(entry.path, nil, false)
  if pid < 0:
    write("[svcmgtd] failed to start ")
    write(entry.name)
    write("\n")
    if entry.required:
      entry.state = srvStopped
      entry.lastFailureReason = cstring("start_failed")
      logEvent(entry.name, cstring("start_failed"))
    else:
      degradeService(entry, cstring("start_failed"))
    return

  if sysServiceRegister(entry.kind, pid) != 0:
    write("[svcmgtd] failed to register ")
    write(entry.name)
    write("\n")
    discard sysKill(pid)
    discard sysWait(pid)
    entry.pid = -1
    if entry.required:
      entry.state = srvStopped
      entry.lastFailureReason = cstring("register_failed")
      logEvent(entry.name, cstring("register_failed"))
    else:
      degradeService(entry, cstring("register_failed"))
    return

  entry.pid = pid
  entry.state = srvStarting
  entry.readyDeadline = sysTicks() + ServiceReadyTimeoutTicks
  entry.lastFailureReason = cstring("none")
  entry.livenessMisses = U32(0)
  logEvent(entry.name, cstring("started"))
  write("[svcmgtd] service started ")
  write(entry.name)
  write(" pid=")
  writeUnsigned(U64(pid))
  write("\n")


proc restartService(entry: ptr ServiceEntry) =
  stopService(entry, cstring("restart_requested"))
  inc entry.restarts
  startService(entry)


proc handleServiceProcessExit(entry: ptr ServiceEntry, reason: cstring) =
  if entry.pid > 0:
    entry.lastExitStatus = sysWait(entry.pid)
  entry.pid = -1
  entry.livenessMisses = U32(0)

  if entry.required:
    write("[svcmgtd] service restarting ")
    write(entry.name)
    write("\n")
    entry.state = srvStopped
    entry.lastFailureReason = reason
    logEvent(entry.name, reason)
    inc entry.restarts
    startService(entry)
  else:
    discard sysServiceUnregister(entry.kind)
    entry.state = srvDegraded
    entry.lastFailureReason = reason
    logEvent(entry.name, reason)
    write("[svcmgtd] service degraded ")
    write(entry.name)
    write("\n")


proc handleExitedServiceSignals() =
  while sysSignalPoll(addr pendingSignal) == 0 and pendingSignal != SysSignalNone:
    if pendingSignal == SysSignalChildExited:
      discard refreshServiceSnapshot()

      var i = 0
      while i < len(services):
        if services[i].pid > 0 and not serviceAlive(addr services[i]):
          handleServiceProcessExit(addr services[i], cstring("process_exit"))
        inc i
