import ../../../lib/types
import ./strutils


const
  PasswdNameMax* = U32(32)
  PasswdHomeMax* = U32(64)
  PasswdLineMax* = U32(128)


type
  PasswdEntry* = object
    name*: array[PasswdNameMax, char]
    uid*: U32
    gid*: U32
    home*: array[PasswdHomeMax, char]


proc clearEntry*(entry: var PasswdEntry) =
  var i = U32(0)
  while i < PasswdNameMax:
    entry.name[i] = '\0'
    inc i

  i = U32(0)
  while i < PasswdHomeMax:
    entry.home[i] = '\0'
    inc i

  entry.uid = U32(0)
  entry.gid = U32(0)


proc copyField(dst: var openArray[char], src: cstring, startPos, endPos: U32): bool =
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


proc parseFieldU32(line: cstring, startPos, endPos: U32, value: var U32): bool =
  var buf: array[16, char]
  if not copyField(buf, line, startPos, endPos):
    return false

  parseU32(cast[cstring](addr buf[0]), value)


proc parsePasswdLine*(line: cstring, entry: var PasswdEntry): bool =
  clearEntry(entry)

  var fields: array[5, U32]
  fields[0] = U32(0)

  var fieldCount = U32(1)
  var pos = U32(0)
  while line[pos] != '\0':
    if line[pos] == ':':
      if fieldCount >= U32(5):
        return false

      fields[fieldCount] = pos + U32(1)
      inc fieldCount
    inc pos

  if fieldCount != U32(4):
    return false

  let nameStart = fields[0]
  let uidStart = fields[1]
  let gidStart = fields[2]
  let homeStart = fields[3]
  let nameEnd = uidStart - U32(1)
  let uidEnd = gidStart - U32(1)
  let gidEnd = homeStart - U32(1)
  var homeEnd = pos
  while homeEnd > homeStart and
      (line[homeEnd - U32(1)] == char(10) or line[homeEnd - U32(1)] == char(13)):
    dec homeEnd

  if nameEnd == nameStart or homeEnd == homeStart:
    return false

  if not copyField(entry.name, line, nameStart, nameEnd):
    return false

  if not parseFieldU32(line, uidStart, uidEnd, entry.uid):
    return false

  if not parseFieldU32(line, gidStart, gidEnd, entry.gid):
    return false

  copyField(entry.home, line, homeStart, homeEnd)


proc writePasswdLine*(dst: pointer, capacity: U32, entry: PasswdEntry): U32 =
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
  appendU32(entry.uid)
  appendChar(':')
  appendU32(entry.gid)
  appendChar(':')
  appendCString(cast[cstring](addr entry.home[0]))
  appendChar('\n')
  pos
