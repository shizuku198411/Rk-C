import ../../../lib/types
import ./strutils


const
  GroupNameMax* = U32(32)
  GroupMembersMax* = U32(96)
  GroupLineMax* = U32(160)


type
  GroupEntry* = object
    name*: array[GroupNameMax, char]
    gid*: U32
    members*: array[GroupMembersMax, char]


proc clearGroupEntry*(entry: var GroupEntry) =
  var i = U32(0)
  while i < GroupNameMax:
    entry.name[i] = '\0'
    inc i

  i = U32(0)
  while i < GroupMembersMax:
    entry.members[i] = '\0'
    inc i

  entry.gid = U32(0)


proc copyGroupField(dst: var openArray[char], src: cstring, startPos, endPos: U32): bool =
  if dst.len == 0:
    return false

  let len = endPos - startPos
  if len + U32(1) > U32(dst.len):
    return false

  var i = U32(0)
  while i < len:
    dst[i] = src[startPos + i]
    inc i

  while i < U32(dst.len):
    dst[i] = '\0'
    inc i

  true


proc parseGroupFieldU32(line: cstring, startPos, endPos: U32, value: var U32): bool =
  var buf: array[16, char]
  if not copyGroupField(buf, line, startPos, endPos):
    return false

  parseU32(cast[cstring](addr buf[0]), value)


proc parseGroupLine*(line: cstring, entry: var GroupEntry): bool =
  clearGroupEntry(entry)

  var fields: array[4, U32]
  fields[0] = U32(0)

  var fieldCount = U32(1)
  var pos = U32(0)
  while line[pos] != '\0':
    if line[pos] == ':':
      if fieldCount >= U32(4):
        return false

      fields[fieldCount] = pos + U32(1)
      inc fieldCount
    inc pos

  if fieldCount != U32(3):
    return false

  let nameStart = fields[0]
  let gidStart = fields[1]
  let membersStart = fields[2]
  let nameEnd = gidStart - U32(1)
  let gidEnd = membersStart - U32(1)
  var membersEnd = pos
  while membersEnd > membersStart and
      (line[membersEnd - U32(1)] == char(10) or line[membersEnd - U32(1)] == char(13)):
    dec membersEnd

  if nameEnd == nameStart:
    return false

  if not copyGroupField(entry.name, line, nameStart, nameEnd):
    return false

  if not parseGroupFieldU32(line, gidStart, gidEnd, entry.gid):
    return false

  copyGroupField(entry.members, line, membersStart, membersEnd)


proc writeGroupLine*(dst: pointer, capacity: U32, entry: GroupEntry): U32 =
  let outBuf = cast[ptr UncheckedArray[char]](dst)
  var pos = U32(0)

  template appendChar(ch: char) =
    if pos + U32(1) < capacity:
      outBuf[pos] = ch
      inc pos
      outBuf[pos] = '\0'

  template appendCString(s: cstring) =
    var i = U32(0)
    while s[i] != '\0':
      appendChar(s[i])
      inc i

  template appendU32(value: U32) =
    var tmp: array[16, char]
    var n = value
    var i = U32(0)
    if n == U32(0):
      appendChar('0')
    else:
      while n > U32(0) and i < U32(16):
        tmp[i] = char(ord('0') + int(n mod U32(10)))
        n = n div U32(10)
        inc i
      while i > U32(0):
        dec i
        appendChar(tmp[i])

  appendCString(cast[cstring](addr entry.name[0]))
  appendChar(':')
  appendU32(entry.gid)
  appendChar(':')
  appendCString(cast[cstring](addr entry.members[0]))
  appendChar('\n')
  pos
