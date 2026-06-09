## Renders service, trap, log, and filesystem status procfs views.

proc ynString(state: U32): cstring =
  if state == 0:
    cstring("no")
  else:
    cstring("yes")


proc renderServices(): U32 =
  clearOut()
  var pos = U32(0)

  let count = sysServiceList(addr services[0], U64(SysServiceRegistryCount))
  if count < 0:
    appendStr(pos, cstring("error\n"))
    return pos

  appendStr(pos, cstring("name\tpid\tregistered\tavailable\n"))

  var i = I32(0)
  while i < count:
    appendStr(pos, cast[cstring](addr services[i].name[0]))
    appendChar(pos, '\t')
    appendI32(pos, services[i].pid)
    appendChar(pos, '\t')
    appendStr(pos, ynString(services[i].registered))
    appendChar(pos, '\t')
    appendStr(pos, ynString(services[i].available))
    appendChar(pos, '\n')
    inc i

  pos


proc renderMounts(): U32 =
  clearOut()
  var pos = U32(0)

  let count = sysFsInfo(addr fsInfos[0], U64(SysFsInfoMaxEntries))
  if count < 0:
    appendStr(pos, cstring("error\n"))
    return pos

  appendStr(pos, cstring("name\tfs\tmount\tflags\n"))

  var i = I32(0)
  while i < count and i < I32(SysFsInfoMaxEntries):
    appendStr(pos, cast[cstring](addr fsInfos[i].name[0]))
    appendChar(pos, '\t')
    appendStr(pos, cast[cstring](addr fsInfos[i].fsType[0]))
    appendChar(pos, '\t')
    appendStr(pos, cast[cstring](addr fsInfos[i].mount[0]))
    appendChar(pos, '\t')
    if fsInfos[i].readonly != U32(0):
      appendStr(pos, cstring("ro"))
    else:
      appendStr(pos, cstring("rw"))
    appendChar(pos, '\n')
    inc i

  pos


proc renderTraps(): U32 =
  clearOut()
  var pos = U32(0)

  if sysTraps(addr traps) != 0:
    appendStr(pos, cstring("error\n"))
    return pos

  appendStr(pos, cstring"timer: ")
  appendU64(pos, traps.supervisorTimer)
  appendChar(pos, '\n')

  appendStr(pos, cstring"external: ")
  appendU64(pos, traps.supervisorExternal)
  appendChar(pos, '\n')

  appendStr(pos, cstring"syscall: ")
  appendU64(pos, traps.environmentCallFromUMode)
  appendChar(pos, '\n')

  appendStr(pos, cstring"load_page_fault: ")
  appendU64(pos, traps.loadPageFault)
  appendChar(pos, '\n')

  appendStr(pos, cstring"store_page_fault: ")
  appendU64(pos, traps.storeAMOPageFault)
  appendChar(pos, '\n')

  appendStr(pos, cstring"inst_page_fault: ")
  appendU64(pos, traps.instructionPageFault)
  appendChar(pos, '\n')

  pos


proc renderKmsg(): U32 =
  clearOut()
  let capacity = U64(ProcFsBufSize - U32(1))
  var kernelLog = newSeq[char](int(ProcFsBufSize))
  let n = sysKmsg(addr kernelLog[0], capacity)
  if n < 0:
    var pos = U32(0)
    appendStr(pos, cstring("error\n"))
    return pos

  var
    pos = U32(0)
    i = U32(0)
  while i < U32(n) and i + U32(1) < ProcFsBufSize:
    appendChar(pos, kernelLog[int(i)])
    inc i

  pos


proc renderFsinfo(): U32 =
  clearOut()
  var pos = U32(0)

  let count = sysFsInfo(addr fsInfos[0], U64(SysFsInfoMaxEntries))
  if count < 0:
    appendStr(pos, cstring("error\n"))
    return pos

  appendStr(pos, cstring("Filesystem\tType\t1K-blocks\tUsed\tAvail\tFiles\tIUsed\tIFree\tRO\tMounted on\n"))

  var i = U32(0)
  while i < U32(count):
    appendStr(pos, cast[cstring](addr fsInfos[i].name[0]))
    appendStr(pos, "\t\t")
    appendStr(pos, cast[cstring](addr fsInfos[i].fsType[0]))
    appendChar(pos, '\t')
    appendKb(pos, fsInfos[i].totalBlocks, fsInfos[i].blockSize)
    appendStr(pos, "\t\t")
    appendKb(pos, fsInfos[i].usedBlocks, fsInfos[i].blockSize)
    appendChar(pos, '\t')
    appendKb(pos, fsInfos[i].freeBlocks, fsInfos[i].blockSize)
    appendChar(pos, '\t')
    appendU64(pos, fsInfos[i].totalFiles)
    appendChar(pos, '\t')
    appendU64(pos, fsInfos[i].usedFiles)
    appendChar(pos, '\t')
    appendU64(pos, fsInfos[i].freeFiles)
    appendChar(pos, '\t')
    appendStr(pos, ynString(fsInfos[i].readonly))
    appendChar(pos, '\t')
    appendStr(pos, cast[cstring](addr fsInfos[i].mount[0]))
    appendChar(pos, '\n')
    inc i

  pos
