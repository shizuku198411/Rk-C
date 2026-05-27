## Provides first-token command completion for the interactive shell.
import ../../lib/core/io
import ../../lib/core/passwd
import ../../lib/core/pathutils
import ../../lib/core/strutils
import ../../lib/core/syscall
import ../../lib/core/userdb
import ./prompt
import ./state

const
  CompletionChunkEntries = 8
  CompletionMaxMatches = 16
  CompletionCandidateMax = PathMax
  CompletionTokenMax = LineMax

var
  completionEntries: array[CompletionChunkEntries, DirEntry]
  completionToken: array[CompletionTokenMax, char]
  completionParent: array[PathMax, char]
  completionLeaf: array[DirEntryNameMax, char]
  completionFullPath: array[PathMax, char]
  completionMatches: array[CompletionMaxMatches, array[CompletionCandidateMax, char]]
  completionMatchCount: int
  completionOverflow: bool


proc clearArray(buf: ptr UncheckedArray[char], cap: int) =
  if buf == nil:
    return

  var i = 0
  while i < cap:
    buf[i] = '\0'
    inc i


proc clearCompletionMatches() =
  completionMatchCount = 0
  completionOverflow = false

  var i = 0
  while i < CompletionMaxMatches:
    var j = 0
    while j < CompletionCandidateMax:
      completionMatches[i][j] = '\0'
      inc j
    inc i


proc cstrToken(): cstring =
  cast[cstring](addr completionToken[0])


proc cstrParent(): cstring =
  cast[cstring](addr completionParent[0])


proc cstrLeaf(): cstring =
  cast[cstring](addr completionLeaf[0])


proc cstrFullPath(): cstring =
  cast[cstring](addr completionFullPath[0])


proc cstrMatch(index: int): cstring =
  cast[cstring](addr completionMatches[index][0])


proc copyToArray(dst: ptr UncheckedArray[char], cap: int, src: cstring): bool =
  if dst == nil or cap <= 0 or src == nil:
    return false

  clearArray(dst, cap)

  var i = 0
  while src[i] != '\0':
    if i + 1 >= cap:
      return false

    dst[i] = src[i]
    inc i

  dst[i] = '\0'
  true


proc appendToArray(dst: ptr UncheckedArray[char], cap: int, pos: var int, src: cstring): bool =
  if dst == nil or cap <= 0 or src == nil:
    return false

  var i = 0
  while src[i] != '\0':
    if pos + 1 >= cap:
      return false

    dst[pos] = src[i]
    inc pos
    inc i

  dst[pos] = '\0'
  true


proc appendCharToArray(dst: ptr UncheckedArray[char], cap: int, pos: var int, ch: char): bool =
  if dst == nil or cap <= 0:
    return false

  if pos + 1 >= cap:
    return false

  dst[pos] = ch
  inc pos
  dst[pos] = '\0'
  true


proc cstringLen(s: cstring): int =
  if s == nil:
    return 0

  var i = 0
  while s[i] != '\0':
    inc i

  i


proc startsWithCString(name, prefix: cstring): bool =
  if name == nil or prefix == nil:
    return false

  var i = 0
  while prefix[i] != '\0':
    if name[i] != prefix[i]:
      return false
    inc i

  true


proc hasSlash(s: cstring): bool =
  if s == nil:
    return false

  var i = 0
  while s[i] != '\0':
    if s[i] == '/':
      return true
    inc i

  false


proc splitPathPrefix(token: cstring): bool =
  clearArray(cast[ptr UncheckedArray[char]](addr completionParent[0]), PathMax)
  clearArray(cast[ptr UncheckedArray[char]](addr completionLeaf[0]), DirEntryNameMax)

  if token == nil:
    return false

  var slashPos = -1
  var endPos = 0

  while token[endPos] != '\0':
    if token[endPos] == '/':
      slashPos = endPos
    inc endPos

  if slashPos < 0:
    return false

  if slashPos == 0:
    completionParent[0] = '/'
    completionParent[1] = '\0'
  else:
    var i = 0
    while i < slashPos:
      if i + 1 >= PathMax:
        return false
      completionParent[i] = token[i]
      inc i
    completionParent[i] = '\0'

  var leafPos = 0
  var srcPos = slashPos + 1
  while token[srcPos] != '\0':
    if leafPos + 1 >= DirEntryNameMax:
      return false

    completionLeaf[leafPos] = token[srcPos]
    inc leafPos
    inc srcPos

  completionLeaf[leafPos] = '\0'
  true


proc buildHomeBinPath(): bool =
  clearArray(cast[ptr UncheckedArray[char]](addr completionFullPath[0]), PathMax)

  var user: PasswdEntry
  if not resolveUid(sysGetUid(), user):
    return false

  var pos = 0
  if not appendToArray(
    cast[ptr UncheckedArray[char]](addr completionFullPath[0]),
    PathMax,
    pos,
    cstring"/home/",
  ):
    return false

  if not appendToArray(
    cast[ptr UncheckedArray[char]](addr completionFullPath[0]),
    PathMax,
    pos,
    cast[cstring](addr user.name[0]),
  ):
    return false

  appendToArray(
    cast[ptr UncheckedArray[char]](addr completionFullPath[0]),
    PathMax,
    pos,
    cstring"/bin",
  )


proc copyCandidateName(dst: ptr UncheckedArray[char], cap: int, name: cstring): bool =
  copyToArray(dst, cap, name)


proc buildExplicitCandidate(parent, name: cstring): bool =
  clearArray(cast[ptr UncheckedArray[char]](addr completionFullPath[0]), PathMax)

  var pos = 0

  if not appendToArray(
    cast[ptr UncheckedArray[char]](addr completionFullPath[0]),
    PathMax,
    pos,
    parent,
  ):
    return false

  if pos == 0 or completionFullPath[pos - 1] != '/':
    if not appendCharToArray(
      cast[ptr UncheckedArray[char]](addr completionFullPath[0]),
      PathMax,
      pos,
      '/',
    ):
      return false

  appendToArray(
    cast[ptr UncheckedArray[char]](addr completionFullPath[0]),
    PathMax,
    pos,
    name,
  )


proc candidateAlreadyExists(name: cstring): bool =
  var i = 0
  while i < completionMatchCount:
    if cstringEq(cstrMatch(i), name):
      return true
    inc i

  false


proc addCandidate(name: cstring) =
  if name == nil or name[0] == '\0':
    return

  if candidateAlreadyExists(name):
    return

  if completionMatchCount >= CompletionMaxMatches:
    completionOverflow = true
    return

  if copyCandidateName(
    cast[ptr UncheckedArray[char]](addr completionMatches[completionMatchCount][0]),
    CompletionCandidateMax,
    name,
  ):
    inc completionMatchCount
  else:
    completionOverflow = true


proc scanDirectoryForPrefix(directory, prefix: cstring, explicitPath: bool) =
  if directory == nil or prefix == nil:
    return

  var offset = U64(0)

  while true:
    let count = sysLsAt(
      directory,
      addr completionEntries[0],
      U64(CompletionChunkEntries),
      offset,
    )

    if count <= 0:
      return

    var i = I32(0)
    while i < count:
      if completionEntries[i].typ == DirEntryTypeFile:
        let name = cast[cstring](addr completionEntries[i].name[0])
        if startsWithCString(name, prefix):
          if explicitPath:
            if buildExplicitCandidate(directory, name):
              addCandidate(cstrFullPath())
          else:
            addCandidate(name)

      inc i

    offset += U64(count)

    if count < I32(CompletionChunkEntries):
      return


proc collectCommandMatches(prefix: cstring) =
  clearCompletionMatches()

  if prefix == nil:
    return

  if hasSlash(prefix):
    if not splitPathPrefix(prefix):
      return

    let parent = resolvePath(cstrParent())
    if parent == nil:
      return

    scanDirectoryForPrefix(parent, cstrLeaf(), true)
    return

  if buildHomeBinPath():
    scanDirectoryForPrefix(cstrFullPath(), prefix, false)

  scanDirectoryForPrefix(cstring"/usr/bin", prefix, false)
  scanDirectoryForPrefix(cstring"/bin", prefix, false)


proc replaceCommandToken(value: cstring, len: var int, cursor: var int): bool =
  if lineBuf == nil or value == nil:
    return false

  let valueLen = cstringLen(value)
  if valueLen + 1 >= lineBufCap:
    return false

  var i = 0
  while i < valueLen:
    lineBuf[i] = value[i]
    inc i

  lineBuf[i] = '\0'

  len = valueLen
  cursor = valueLen
  true


proc redrawInputLine(len, cursor: int) =
  printPrompt()

  var i = 0
  while i < len:
    writeChar(lineBuf[i])
    inc i

  var back = len - cursor
  while back > 0:
    write("\x1b[D")
    dec back


proc printCandidates(len, cursor: int) =
  write("\n")

  var i = 0
  while i < completionMatchCount:
    write(cstrMatch(i))
    if i + 1 < completionMatchCount:
      write("  ")
    inc i

  if completionOverflow:
    write("  ...")

  write("\n")
  redrawInputLine(len, cursor)


proc extractCommandToken(len, cursor: int): bool =
  clearArray(cast[ptr UncheckedArray[char]](addr completionToken[0]), CompletionTokenMax)

  if lineBuf == nil:
    return false

  var firstSpace = len
  var i = 0
  while i < len:
    if lineBuf[i] == ' ':
      firstSpace = i
      break
    inc i

  # First step only completes the command token.
  # If the cursor is after the first separator, argument completion is ignored.
  if cursor > firstSpace:
    return false

  if firstSpace + 1 >= CompletionTokenMax:
    return false

  i = 0
  while i < firstSpace:
    completionToken[i] = lineBuf[i]
    inc i

  completionToken[i] = '\0'
  true


## Completes the first shell token as a command name.
##
## Returns true when Tab was handled by the completion layer.
proc completeCommandAtCursor*(len: var int, cursor: var int): bool =
  if not extractCommandToken(len, cursor):
    return true

  collectCommandMatches(cstrToken())

  if completionMatchCount == 0:
    return true

  if completionMatchCount == 1:
    if replaceCommandToken(cstrMatch(0), len, cursor):
      write("\r")
      write("\x1b[2K")
      redrawInputLine(len, cursor)
    return true

  printCandidates(len, cursor)
  true
