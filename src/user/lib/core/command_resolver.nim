## Resolves command names to executable paths using the userspace search policy.
import ./passwd
import ./pathutils
import ./path_buffer
import ./strutils
import ./syscall
import ./userdb


const
  ResolverChunkEntries = 8


type
  CommandResolveStatus* = enum
    CommandResolved,
    CommandNotFound,
    CommandPathTooLong


var
  candidatePath: array[PathMax, char]
  normalizedPath: array[PathMax, char]
  parentPath: array[PathMax, char]
  leafName: array[DirEntryNameMax, char]
  dirEntries: array[ResolverChunkEntries, DirEntry]


## Builds one searched command path from its directory and executable name.
proc buildCandidate(directory, command: cstring): bool =
  clearBuffer(cast[ptr UncheckedArray[char]](addr candidatePath[0]), PathMax)
  var pos = 0
  if not appendCString(
    cast[ptr UncheckedArray[char]](addr candidatePath[0]),
    PathMax,
    pos,
    directory,
  ):
    return false

  if pos == 0 or candidatePath[pos - 1] != '/':
    if not appendCString(
      cast[ptr UncheckedArray[char]](addr candidatePath[0]),
      PathMax,
      pos,
      cstring"/",
    ):
      return false

  appendCString(
    cast[ptr UncheckedArray[char]](addr candidatePath[0]),
    PathMax,
    pos,
    command,
  )


## Returns whether a command contains an explicit path separator.
proc hasSlash(command: cstring): bool =
  var i = 0
  while command[i] != '\0':
    if command[i] == '/':
      return true

    inc i

  false


## Splits an absolute candidate path into parent directory and leaf name.
proc splitCandidate(path: cstring): bool =
  var slashPos = -1
  var endPos = 0
  while path[endPos] != '\0':
    if path[endPos] == '/':
      slashPos = endPos
    inc endPos

  if slashPos < 0 or slashPos + 1 >= endPos:
    return false

  clearBuffer(cast[ptr UncheckedArray[char]](addr parentPath[0]), PathMax)
  clearBuffer(cast[ptr UncheckedArray[char]](addr leafName[0]), DirEntryNameMax)

  if slashPos == 0:
    parentPath[0] = '/'
    parentPath[1] = '\0'
  else:
    var i = 0
    while i < slashPos:
      parentPath[i] = path[i]
      inc i
    parentPath[slashPos] = '\0'

  var leafPos = 0
  var srcPos = slashPos + 1
  while path[srcPos] != '\0':
    if leafPos + 1 >= DirEntryNameMax:
      return false

    leafName[leafPos] = path[srcPos]
    inc leafPos
    inc srcPos

  leafName[leafPos] = '\0'
  true


## Returns whether the candidate names an existing non-directory entry.
proc candidateExists(path: cstring): bool =
  if not splitCandidate(path):
    return false

  var offset = U64(0)
  while true:
    let count = sysLsAt(
      cast[cstring](addr parentPath[0]),
      addr dirEntries[0],
      U64(ResolverChunkEntries),
      offset,
    )
    if count <= 0:
      return false

    var i = I32(0)
    while i < count:
      if dirEntries[i].typ == DirEntryTypeFile and
          fixedCStringEq(dirEntries[i].name, cast[cstring](addr leafName[0])):
        return true

      inc i

    offset += U64(count)
    if count < I32(ResolverChunkEntries):
      return false


## Copies a found candidate into the caller-provided stable path buffer.
proc returnCandidate(outBuf: ptr UncheckedArray[char], outCap: int): CommandResolveStatus =
  if not copyCStringInto(outBuf, outCap, cast[cstring](addr candidatePath[0])):
    return CommandPathTooLong

  CommandResolved


## Resolves an executable command into an absolute path without executing it.
proc resolveCommandInto*(command: cstring, outBuf: ptr UncheckedArray[char],
                         outCap: int): CommandResolveStatus =
  if isEmpty(command) or outBuf == nil or outCap <= 0:
    return CommandNotFound

  clearBuffer(outBuf, outCap)

  if hasSlash(command):
    let path = resolvePathInto(command, normalizedPath)
    if path == nil or not copyCStringInto(
      cast[ptr UncheckedArray[char]](addr candidatePath[0]),
      PathMax,
      path,
    ):
      return CommandPathTooLong

    if candidateExists(cast[cstring](addr candidatePath[0])):
      return returnCandidate(outBuf, outCap)

    if not copyCStringInto(outBuf, outCap, cast[cstring](addr candidatePath[0])):
      return CommandPathTooLong

    return CommandNotFound

  var user: PasswdEntry
  if resolveUid(sysGetUid(), user):
    clearBuffer(cast[ptr UncheckedArray[char]](addr normalizedPath[0]), PathMax)
    var pos = 0
    if appendCString(
      cast[ptr UncheckedArray[char]](addr normalizedPath[0]),
      PathMax,
      pos,
      cstring"/home/",
    ) and appendCString(
      cast[ptr UncheckedArray[char]](addr normalizedPath[0]),
      PathMax,
      pos,
      cast[cstring](addr user.name[0]),
    ) and appendCString(
      cast[ptr UncheckedArray[char]](addr normalizedPath[0]),
      PathMax,
      pos,
      cstring"/bin",
    ):
      if not buildCandidate(cast[cstring](addr normalizedPath[0]), command):
        return CommandPathTooLong
      if candidateExists(cast[cstring](addr candidatePath[0])):
        return returnCandidate(outBuf, outCap)

  if not buildCandidate(cstring"/usr/bin", command):
    return CommandPathTooLong
  if candidateExists(cast[cstring](addr candidatePath[0])):
    return returnCandidate(outBuf, outCap)

  if not buildCandidate(cstring"/bin", command):
    return CommandPathTooLong
  if candidateExists(cast[cstring](addr candidatePath[0])):
    return returnCandidate(outBuf, outCap)

  if not copyCStringInto(outBuf, outCap, cast[cstring](addr candidatePath[0])):
    return CommandPathTooLong

  CommandNotFound


## Resolves a command for execution while leaving explicit path access checks to exec.
proc resolveExecutableInto*(command: cstring, outBuf: ptr UncheckedArray[char],
                            outCap: int): CommandResolveStatus =
  if isEmpty(command) or outBuf == nil or outCap <= 0:
    return CommandNotFound

  if not hasSlash(command):
    return resolveCommandInto(command, outBuf, outCap)

  let path = resolvePathInto(command, normalizedPath)
  if path == nil or not copyCStringInto(outBuf, outCap, path):
    return CommandPathTooLong

  CommandResolved
