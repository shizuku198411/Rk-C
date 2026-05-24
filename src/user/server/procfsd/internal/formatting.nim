## Formats procfs response text and virtual directory entries.

proc clearOut() =
  var i = U32(0)
  while i < ProcFsBufSize:
    outBuf[i] = '\0'
    inc i


proc appendChar(pos: var U32, ch: char) =
  if pos + U32(1) < ProcFsBufSize:
    outBuf[pos] = ch
    inc pos
    outBuf[pos] = '\0'


proc appendStr(pos: var U32, s: cstring) =
  var i = U32(0)
  while s[i] != '\0':
    appendChar(pos, s[i])
    inc i


proc appendU64(pos: var U32, value: U64) =
  var
    tmp: array[32, char]
    n = value
    i = 0

  if n == 0:
    appendChar(pos, '0')
    return

  while n > 0 and i < 32:
    tmp[i] = char(ord('0') + int(n mod U64(10)))
    n = n div U64(10)
    inc i

  while i > 0:
    dec i
    appendChar(pos, tmp[i])


proc appendI32(pos: var U32, value: I32) =
  if value < 0:
    appendChar(pos, '-')
    appendU64(pos, U64(-value))
  else:
    appendU64(pos, U64(value))


proc appendPercent(pos: var U32, value: U32) =
  appendU64(pos, U64(value))
  appendChar(pos, '%')


proc appendPages(pos: var U32, value: U64) =
  appendU64(pos, value)
  appendChar(pos, 'p')


proc appendKb(pos: var U32, blocks, blockSize: U64) =
  let bytes = blocks * blockSize
  appendU64(pos, (bytes + U64(1023)) div U64(1024))


proc appendTwoDigits(pos: var U32, value: U64) =
  appendChar(pos, char(ord('0') + int((value div U64(10)) mod U64(10))))
  appendChar(pos, char(ord('0') + int(value mod U64(10))))


proc appendDuration(pos: var U32, ticks: U64) =
  let ticksPerSecond = U64(1000) div ProcFsTickMillis
  let totalSeconds = ticks div ticksPerSecond
  let hours = totalSeconds div U64(3600)
  let minutes = (totalSeconds div U64(60)) mod U64(60)
  let seconds = totalSeconds mod U64(60)

  appendTwoDigits(pos, hours)
  appendChar(pos, ':')
  appendTwoDigits(pos, minutes)
  appendChar(pos, ':')
  appendTwoDigits(pos, seconds)


proc appendHex64(pos: var U32, value: U64) =
  appendStr(pos, cstring("0x"))

  var shift = 60
  var started = false
  while shift >= 0:
    let nibble = int((value shr U64(shift)) and U64(0xf))
    if nibble != 0 or started or shift == 0:
      started = true
      if nibble < 10:
        appendChar(pos, char(ord('0') + nibble))
      else:
        appendChar(pos, char(ord('a') + nibble - 10))
    shift -= 4


proc appendRkxMapLine(pos: var U32, start, size: U64, perms, name: cstring) =
  if size == 0:
    return

  appendHex64(pos, start)
  appendChar(pos, '-')
  appendHex64(pos, start + size)
  appendChar(pos, ' ')
  appendStr(pos, perms)
  appendChar(pos, ' ')
  appendStr(pos, name)
  appendChar(pos, '\n')


proc appendCapName(pos: var U32, mask: U32, cap: U32, name: cstring, first: var bool) =
  if (mask and cap) == 0:
    return

  if not first:
    appendChar(pos, ',')
  appendStr(pos, name)
  first = false


proc appendCapNames(pos: var U32, mask: U32) =
  if mask == SysCapNone:
    appendStr(pos, cstring("none"))
    return

  var first = true
  appendCapName(pos, mask, SysCapServiceManager, cstring(SysCapServiceManagerName), first)
  appendCapName(pos, mask, SysCapRawFs, cstring(SysCapRawFsName), first)
  appendCapName(pos, mask, SysCapRawBlock, cstring(SysCapRawBlockName), first)
  appendCapName(pos, mask, SysCapRawNet, cstring(SysCapRawNetName), first)
  appendCapName(pos, mask, SysCapProcessList, cstring(SysCapProcessListName), first)
  appendCapName(pos, mask, SysCapProcessKill, cstring(SysCapProcessKillName), first)
  appendCapName(pos, mask, SysCapTrace, cstring(SysCapTraceName), first)
  appendCapName(pos, mask, SysCapShutdown, cstring(SysCapShutdownName), first)

  let unknown = mask and (not SysCapAllKnown)
  if unknown != SysCapNone:
    if not first:
      appendChar(pos, ' ')
    appendStr(pos, cstring("unknown:"))
    appendHex64(pos, U64(unknown))


proc appendCapMaskLine(pos: var U32, label: cstring, mask: U32) =
  appendStr(pos, label)
  appendStr(pos, cstring(": "))
  appendHex64(pos, U64(mask))
  appendStr(pos, cstring(" ("))
  appendCapNames(pos, mask)
  appendStr(pos, cstring(")\n"))


proc appendSignalName(pos: var U32, mask, bit: U32, name: cstring, first: var bool) =
  if (mask and bit) == 0:
    return

  if not first:
    appendChar(pos, ',')
  appendStr(pos, name)
  first = false


proc signalMask(signal: U32): U32 =
  U32(1'u32 shl signal)


proc appendSignalNames(pos: var U32, mask: U32) =
  if mask == U32(0):
    appendStr(pos, cstring("none"))
    return

  var first = true
  appendSignalName(pos, mask, signalMask(SysSignalTerminate), cstring("terminate"), first)
  appendSignalName(pos, mask, signalMask(SysSignalInterrupt), cstring("interrupt"), first)
  appendSignalName(pos, mask, signalMask(SysSignalChildExited), cstring("child_exited"), first)
  appendSignalName(pos, mask, signalMask(SysSignalServiceStopped), cstring("service_stopped"), first)


proc appendSignalMaskLine(pos: var U32, label: cstring, mask: U32) =
  appendStr(pos, label)
  appendStr(pos, cstring(": "))
  appendHex64(pos, U64(mask))
  appendStr(pos, cstring(" ("))
  appendSignalNames(pos, mask)
  appendStr(pos, cstring(")\n"))


proc clearResponseData() =
  var i = U32(0)
  while i < SysIpcMessageMax:
    response.data[i] = '\0'
    inc i


proc writeDirEntry(entry: ptr DirEntry, name: cstring, typ: U32) =
  entry.typ = typ
  entry.size = 0

  var i = 0
  while i + 1 < DirEntryNameMax and name[i] != '\0':
    entry.name[i] = name[i]
    inc i

  entry.name[i] = '\0'


proc writePidDirEntry(entry: ptr DirEntry, pid: I32) =
  entry.typ = DirEntryTypeDir
  entry.size = 0

  var tmp: array[16, char]
  var n = pid
  var i = 0

  if n <= 0:
    entry.name[0] = '0'
    entry.name[1] = '\0'
    return

  while n > 0 and i < 16:
    tmp[i] = char(ord('0') + int(n mod I32(10)))
    n = n div I32(10)
    inc i

  var pos = 0
  while i > 0 and pos + 1 < DirEntryNameMax:
    dec i
    entry.name[pos] = tmp[i]
    inc pos

  entry.name[pos] = '\0'


