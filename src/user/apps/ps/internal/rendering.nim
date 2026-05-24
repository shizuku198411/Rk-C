## Sorts, filters, and renders process snapshots using an ORC-managed builder.

var renderedText: string = ""


## Clears the ORC-managed output builder for one command result.
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


## Flushes the ORC-managed output builder to stdout.
proc flushRenderedText() =
  if renderedText.len > 0:
    discard sysWriteFd(1, addr renderedText[0], U64(renderedText.len))


## Converts a process state code to a fixed-width display label.
proc stateName(state: U32): cstring =
  if state == SysProcessRunnable:
    "runnable"
  elif state == SysProcessRunning:
    "running "
  elif state == SysProcessSleeping:
    "sleeping"
  elif state == SysProcessZombie:
    "zombie  "
  else:
    "unused  "


## Converts the user/kernel process flag to a display label.
proc modeName(isUser: U32): cstring =
  if isUser != 0:
    "user"
  else:
    "kernel"


## Appends a signed pid value to the output builder.
proc appendPid(pid: I32) =
  if pid < 0:
    appendChar('-')
    appendUnsigned(U64(-pid))
  else:
    appendUnsigned(U64(pid))


## Appends a CPU usage percentage to the output builder.
proc appendCpuPercent(value: U32) =
  appendUnsigned(U64(value))
  appendChar('%')


## Appends a memory usage value in pages to the output builder.
proc appendMemoryPages(value: U64) =
  appendUnsigned(value)
  appendChar('p')


## Appends one process row using the selected ps format.
proc appendProcess(entry: ptr SysProcessInfo, full, longFormat: bool) =
  var
    userEntry: PasswdEntry
    groupEntry: GroupEntry

  appendPid(entry.pid)
  if not full and not longFormat:
    appendChar('\t')
    appendText(cast[cstring](addr entry.exePath[0]))
    appendChar('\n')
    return

  appendChar('\t')
  appendPid(entry.ppid)
  appendChar('\t')
  if resolveUid(entry.uid, userEntry):
    appendText(cast[cstring](addr userEntry.name[0]))
  else:
    appendUnsigned(U64(entry.uid))
  appendChar('\t')
  if resolveGid(entry.gid, groupEntry):
    appendText(cast[cstring](addr groupEntry.name[0]))
  else:
    appendUnsigned(U64(entry.gid))
  appendChar('\t')
  appendText(stateName(entry.state))
  appendChar('\t')
  appendText(modeName(entry.isUser))
  if longFormat:
    appendChar('\t')
    appendCpuPercent(entry.cpuPercent)
    appendChar('\t')
    appendMemoryPages(entry.memoryPages)
  appendChar('\t')
  appendText(cast[cstring](addr entry.exePath[0]))
  appendChar('\n')


## Sorts process entries by pid in ascending order.
proc sortProcessByPid(entries: var seq[SysProcessInfo], count: I32) =
  var i = 1

  while i < count:
    let key = entries[i]
    var j = i

    while j > 0 and entries[j - 1].pid > key.pid:
      entries[j] = entries[j - 1]
      dec j

    entries[j] = key
    inc i


## Finds the index of a process entry by pid.
proc findEntryIndex(pid: I32, count: I32): I32 =
  var i = I32(0)
  while i < count:
    if entries[i].pid == pid:
      return i
    inc i

  -1


## Returns whether a pid belongs to the subtree rooted at rootPid.
proc isDescendantOf(pid, rootPid: I32, count: I32): bool =
  var cur = pid
  var depth = I32(0)

  while cur > 0 and depth < count:
    if cur == rootPid:
      return true

    let idx = findEntryIndex(cur, count)
    if idx < 0:
      return false

    cur = entries[idx].ppid
    inc depth

  false


## Decides whether a process should be visible in the selected view.
proc shouldPrintProcess(entry: ptr SysProcessInfo, count: I32, fullList: bool): bool =
  if entry.state == SysProcessUnused:
    return false

  if entry.pid == 1:
    return false

  if fullList:
    return true

  let selfPid = sysGetPid()
  let selfIdx = findEntryIndex(selfPid, count)
  if selfIdx < 0:
    return true

  let rootPid = entries[selfIdx].ppid
  if rootPid <= 0:
    return true

  entry.pid == rootPid or isDescendantOf(entry.pid, rootPid, count)


## Appends the ps header for the selected format.
proc appendHeader(full, longFormat: bool) =
  if full or longFormat:
    appendText(cstring("pid\tppid\tuid\tgid\tstate\t\tmode"))
    if longFormat:
      appendText(cstring("\tcpu\tmem"))
    appendText(cstring("\texe\n"))
  else:
    appendText(cstring("pid\texe\n"))


## Sorts, renders, and prints all selected process entries.
proc printProcesses(count: I32, full, every, longFormat: bool) =
  sortProcessByPid(entries, count)

  clearRenderedText()
  appendHeader(full, longFormat)
  var i = I32(0)
  while i < count:
    if shouldPrintProcess(addr entries[i], count, every):
      appendProcess(addr entries[i], full, longFormat)
    inc i

  flushRenderedText()
