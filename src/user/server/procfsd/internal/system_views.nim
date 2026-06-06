## Renders procfs host and process-list information files.

proc renderUptime(): U32 =
  clearOut()
  var pos = U32(0)
  let ticks = sysTicks()

  appendStr(pos, cstring("uptime: "))
  appendDuration(pos, ticks)
  appendChar(pos, '\n')

  appendStr(pos, cstring("ticks: "))
  appendU64(pos, ticks)
  appendChar(pos, '\n')
  pos


proc renderMeminfo(): U32 =
  clearOut()
  var pos = U32(0)

  if sysGetBitMap(addr bitmap) < 0:
    appendStr(pos, cstring("error\n"))
    return pos

  appendStr(pos, cstring("total: "))
  appendU64(pos, bitmap.total)
  appendStr(pos, cstring(" pages\n"))

  appendStr(pos, cstring("used : "))
  appendU64(pos, bitmap.used)
  appendStr(pos, cstring(" pages\n"))

  appendStr(pos, cstring("free : "))
  appendU64(pos, bitmap.free)
  appendStr(pos, cstring(" pages\n"))

  pos


proc renderCpuinfo(): U32 =
  clearOut()
  var pos = U32(0)

  if sysCpuStaticInfo(addr cpuStaticInfo) < 0:
    appendStr(pos, cstring("error\n"))
    return pos

  appendStr(pos, cstring("platform: "))
  appendStr(pos, cast[cstring](addr cpuStaticInfo.platform[0]))
  appendChar(pos, '\n')

  appendStr(pos, cstring("soc: "))
  appendStr(pos, cast[cstring](addr cpuStaticInfo.soc[0]))
  appendChar(pos, '\n')

  appendStr(pos, cstring("cpu: "))
  appendStr(pos, cast[cstring](addr cpuStaticInfo.cpu[0]))
  appendChar(pos, '\n')

  appendStr(pos, cstring("hart_count: "))
  appendU64(pos, U64(cpuStaticInfo.hartCount))
  appendChar(pos, '\n')

  appendStr(pos, cstring("boot_hart: "))
  appendU64(pos, cpuStaticInfo.bootHartId)
  appendChar(pos, '\n')

  appendStr(pos, cstring("isa: "))
  appendStr(pos, cast[cstring](addr cpuStaticInfo.isa[0]))
  appendChar(pos, '\n')

  appendStr(pos, cstring("mmu: "))
  appendStr(pos, cast[cstring](addr cpuStaticInfo.mmu[0]))
  appendChar(pos, '\n')

  appendStr(pos, cstring("timebase_hz: "))
  if cpuStaticInfo.timebaseHz == U64(0):
    appendStr(pos, cstring("unknown"))
  else:
    appendU64(pos, cpuStaticInfo.timebaseHz)
  appendChar(pos, '\n')

  appendStr(pos, cstring("core_clock_hz: "))
  if cpuStaticInfo.coreClockHz == U64(0):
    appendStr(pos, cstring("unknown"))
  else:
    appendU64(pos, cpuStaticInfo.coreClockHz)
  appendStr(pos, cstring("\n\n"))

  if sysCpuInfo(addr cpuInfo) < 0:
    appendStr(pos, cstring("error\n"))
    return pos

  appendStr(pos, cstring("total_ticks: "))
  appendU64(pos, cpuInfo.totalTicks)
  appendChar(pos, '\n')

  appendStr(pos, cstring("window_ticks: "))
  appendU64(pos, cpuInfo.windowTicks)
  appendChar(pos, '\n')

  appendStr(pos, cstring("idle_ticks  : "))
  appendU64(pos, cpuInfo.idleTicks)
  appendChar(pos, '\n')

  appendStr(pos, cstring("busy_ticks  : "))
  appendU64(pos, cpuInfo.busyTicks)
  appendChar(pos, '\n')

  appendStr(pos, cstring("usage       : "))
  appendU64(pos, U64(cpuInfo.usagePercent))
  appendStr(pos, cstring("%\n"))

  pos


proc renderTty(): U32 =
  clearOut()
  var pos = U32(0)

  if sysConsoleInfo(addr consoleInfo) < 0:
    appendStr(pos, cstring("error\n"))
    return pos

  appendStr(pos, cstring("capacity: "))
  appendU64(pos, consoleInfo.capacity)
  appendChar(pos, '\n')

  appendStr(pos, cstring("buffered: "))
  appendU64(pos, consoleInfo.buffered)
  appendChar(pos, '\n')

  appendStr(pos, cstring("received: "))
  appendU64(pos, consoleInfo.received)
  appendChar(pos, '\n')

  appendStr(pos, cstring("full_events: "))
  appendU64(pos, consoleInfo.fullEvents)
  appendChar(pos, '\n')

  appendStr(pos, cstring("dropped: "))
  appendU64(pos, consoleInfo.dropped)
  appendChar(pos, '\n')

  appendStr(pos, cstring("overrun_errors: "))
  appendU64(pos, consoleInfo.overrunErrors)
  appendChar(pos, '\n')

  appendStr(pos, cstring("line_errors: "))
  appendU64(pos, consoleInfo.lineErrors)
  appendChar(pos, '\n')

  pos


proc userName(user: U32): cstring =
  if user == 0:
    cstring("kernel")
  else:
    cstring("user")


proc stateName(state: U32): cstring =
  if state == SysProcessRunnable:
    cstring("runnable")
  elif state == SysProcessRunning:
    cstring("running ")
  elif state == SysProcessSleeping:
    cstring("sleeping")
  elif state == SysProcessZombie:
    cstring("zombie  ")
  else:
    cstring("unused  ")


proc renderProcesses(): U32 =
  clearOut()
  var pos = U32(0)

  let count = sysPs(addr procInfos[0], U64(SysProcessMaxSlots), SysProcListAllSlots)
  if count < 0:
    appendStr(pos, cstring("error\n"))
    return pos

  appendStr(pos, cstring("pid\tppid\tuid\tgid\tstate\tuser\tcpu\tmem\texe\n"))

  var
    i = I32(0)
    entry: PasswdEntry
    group: GroupEntry

  while i < count:
    if procInfos[i].state != SysProcessUnused:
      appendI32(pos, procInfos[i].pid)
      appendChar(pos, '\t')
      appendI32(pos, procInfos[i].ppid)
      appendChar(pos, '\t')
      if resolveUid(procInfos[i].uid, entry):
        appendStr(pos, cast[cstring](addr entry.name[0]))
      else:
        appendU64(pos, U64(procInfos[i].uid))
      appendChar(pos, '\t')
      if resolveGid(procInfos[i].gid, group):
        appendStr(pos, cast[cstring](addr group.name[0]))
      else:
        appendU64(pos, U64(procInfos[i].gid))
      appendChar(pos, '\t')
      appendStr(pos, stateName(procInfos[i].state))
      appendChar(pos, '\t')
      appendStr(pos, userName(procInfos[i].isUser))
      appendChar(pos, '\t')
      appendPercent(pos, procInfos[i].cpuPercent)
      appendChar(pos, '\t')
      appendPages(pos, procInfos[i].memoryPages)
      appendChar(pos, '\t')
      appendStr(pos, cast[cstring](addr procInfos[i].exePath[0]))
      appendChar(pos, '\n')
    inc i

  pos
