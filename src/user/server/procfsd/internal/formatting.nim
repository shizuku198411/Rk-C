## Builds request-local managed procfs text and fixed virtual directory entries.

## Releases prior rendered text before constructing the current virtual file.
proc clearOut() =
  renderedText = ""
  renderLen = U32(0)


## Appends one character to the capped ORC-managed response builder.
proc appendChar(pos: var U32, ch: char) =
  if measuringOutput:
    if pos < high(U32):
      inc pos
    return

  if pos >= renderOffset and renderLen < renderCapacity:
    renderedText.add(ch)
    inc renderLen

  if pos < high(U32):
    inc pos


## Appends a zero-terminated character sequence to the managed builder.
proc appendStr(pos: var U32, s: cstring) =
  var i = U32(0)
  while s[i] != '\0':
    appendChar(pos, s[i])
    inc i


## Appends an unsigned decimal integer to the managed builder.
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


## Appends a signed decimal integer to the managed builder.
proc appendI32(pos: var U32, value: I32) =
  if value < 0:
    appendChar(pos, '-')
    appendU64(pos, U64(-value))
  else:
    appendU64(pos, U64(value))


## Appends a percentage value to the managed builder.
proc appendPercent(pos: var U32, value: U32) =
  appendU64(pos, U64(value))
  appendChar(pos, '%')


## Appends a page-count value to the managed builder.
proc appendPages(pos: var U32, value: U64) =
  appendU64(pos, value)
  appendChar(pos, 'p')


## Appends a block count converted to rounded-up KiB.
proc appendKb(pos: var U32, blocks, blockSize: U64) =
  let bytes = blocks * blockSize
  appendU64(pos, (bytes + U64(1023)) div U64(1024))


## Appends the low two decimal digits of a value.
proc appendTwoDigits(pos: var U32, value: U64) =
  appendChar(pos, char(ord('0') + int((value div U64(10)) mod U64(10))))
  appendChar(pos, char(ord('0') + int(value mod U64(10))))


## Appends tick time using an hours, minutes, and seconds representation.
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


## Appends a compact hexadecimal value to the managed builder.
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


## Appends one RKX virtual memory mapping row.
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


## Appends a named capability when its entry bit is present in a mask.
proc appendCapName(pos: var U32, mask: U32, entry: UserCapabilityNameEntry,
                   first: var bool) =
  if (mask and entry.bit) == 0:
    return

  if not first:
    appendChar(pos, ',')
  appendStr(pos, entry.name)
  first = false


## Appends the recognized names represented by a capability mask.
proc appendCapNames(pos: var U32, mask: U32) =
  if capMaskIsNone(mask):
    appendStr(pos, cstring("none"))
    return

  var first = true
  for entry in UserCapabilityNameEntries:
    appendCapName(pos, mask, entry, first)

  let unknown = unknownCapabilityMask(mask)
  if not capMaskIsNone(unknown):
    if not first:
      appendChar(pos, ' ')
    appendStr(pos, cstring("unknown:"))
    appendHex64(pos, U64(unknown))


## Appends one labeled capability mask row.
proc appendCapMaskLine(pos: var U32, label: cstring, mask: U32) =
  appendStr(pos, label)
  appendStr(pos, cstring(": "))
  appendHex64(pos, U64(mask))
  appendStr(pos, cstring(" ("))
  appendCapNames(pos, mask)
  appendStr(pos, cstring(")\n"))


## Appends a named pending signal when its bit is present in a mask.
proc appendSignalName(pos: var U32, mask, bit: U32, name: cstring, first: var bool) =
  if (mask and bit) == 0:
    return

  if not first:
    appendChar(pos, ',')
  appendStr(pos, name)
  first = false


## Returns the bit mask for one supported signal number.
proc signalMask(signal: U32): U32 =
  U32(1'u32 shl signal)


## Appends the recognized names represented by a pending signal mask.
proc appendSignalNames(pos: var U32, mask: U32) =
  if mask == U32(0):
    appendStr(pos, cstring("none"))
    return

  var first = true
  appendSignalName(pos, mask, signalMask(SysSignalTerminate), cstring("terminate"), first)
  appendSignalName(pos, mask, signalMask(SysSignalInterrupt), cstring("interrupt"), first)
  appendSignalName(pos, mask, signalMask(SysSignalChildExited), cstring("child_exited"), first)
  appendSignalName(pos, mask, signalMask(SysSignalServiceStopped), cstring("service_stopped"), first)


## Appends one labeled pending-signal mask row.
proc appendSignalMaskLine(pos: var U32, label: cstring, mask: U32) =
  appendStr(pos, label)
  appendStr(pos, cstring(": "))
  appendHex64(pos, U64(mask))
  appendStr(pos, cstring(" ("))
  appendSignalNames(pos, mask)
  appendStr(pos, cstring(")\n"))


## Clears the fixed IPC directory-entry response data buffer.
proc clearResponseData() =
  var i = U32(0)
  while i < SysIpcMessageMax:
    response.data[i] = '\0'
    inc i


## Writes one named virtual directory entry into the fixed IPC response data.
proc writeDirEntry(entry: ptr DirEntry, name: cstring, typ: U32) =
  entry.typ = typ
  entry.size = 0

  var i = 0
  while i + 1 < DirEntryNameMax and name[i] != '\0':
    entry.name[i] = name[i]
    inc i

  entry.name[i] = '\0'


## Writes one process-id virtual directory entry into the fixed IPC response data.
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
