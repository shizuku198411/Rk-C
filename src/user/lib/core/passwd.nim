## Parses and writes passwd records and reads login-style input lines.
import ../../../lib/types
import ./io
import ./strutils


const
  PasswdNameMax* = U32(32)
  PasswdHomeMax* = U32(64)
  PasswdLineMax* = U32(128)

  LoginLineMax* = 64


type
  PasswdEntry* = object
    name*: array[PasswdNameMax, char]
    uid*: U32
    gid*: U32
    home*: array[PasswdHomeMax, char]


## Resets a passwd entry to empty strings and zero ids.
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


## Copies one delimited passwd field into a fixed-size destination buffer.
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


## Parses a delimited passwd field as an unsigned 32-bit integer.
proc parseFieldU32(line: cstring, startPos, endPos: U32, value: var U32): bool =
  var buf: array[16, char]
  if not copyField(buf, line, startPos, endPos):
    return false

  parseU32(cast[cstring](addr buf[0]), value)


## Trims CR/LF bytes from the end of a passwd line field.
proc trimLineEnd(line: cstring, startPos, pos: U32): U32 =
  var endPos = pos
  while endPos > startPos and
      (line[endPos - U32(1)] == char(10) or line[endPos - U32(1)] == char(13)):
    dec endPos

  endPos


## Parses one passwd database line into a PasswdEntry.
proc parsePasswdLine*(line: cstring, entry: var PasswdEntry): bool =
  clearEntry(entry)

  var fields: array[6, U32]
  fields[0] = U32(0)

  var fieldCount = U32(1)
  var pos = U32(0)
  while line[pos] != '\0':
    if line[pos] == ':':
      if fieldCount >= U32(6):
        return false

      fields[fieldCount] = pos + U32(1)
      inc fieldCount
    inc pos

  if fieldCount != U32(4) and fieldCount != U32(5):
    return false

  let nameStart = fields[0]
  let uidStart = fields[1]
  let gidStart = fields[2]
  let homeStart = fields[3]
  let nameEnd = uidStart - U32(1)
  let uidEnd = gidStart - U32(1)
  let gidEnd = homeStart - U32(1)
  let homeEnd =
    if fieldCount == U32(5):
      fields[4] - U32(1)
    else:
      trimLineEnd(line, homeStart, pos)

  if nameEnd == nameStart or homeEnd == homeStart:
    return false

  if not copyField(entry.name, line, nameStart, nameEnd):
    return false

  if not parseFieldU32(line, uidStart, uidEnd, entry.uid):
    return false

  if not parseFieldU32(line, gidStart, gidEnd, entry.gid):
    return false

  if not copyField(entry.home, line, homeStart, homeEnd):
    return false

  true


## Writes one PasswdEntry as a passwd database line.
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


## Writes the public passwd representation returned to clients.
proc writePasswdPublicLine*(dst: pointer, capacity: U32, entry: PasswdEntry): U32 =
  writePasswdLine(dst, capacity, entry)


## Clears a login input buffer.
proc clearBuf(buf: var array[LoginLineMax, char]) =
  var i = 0
  while i < LoginLineMax:
    buf[i] = '\0'
    inc i


## Reads a login or password line with optional terminal echo.
proc readLoginLine*(buf: var array[LoginLineMax, char], echo: bool): cstring =
  clearBuf(buf)

  var len = 0
  while true:
    let ch = readChar()
    if ch == '\r' or ch == '\n':
      buf[len] = '\0'
      write("\n")
      return cast[cstring](addr buf[0])

    if ch == '\b' or ch == char(127):
      if len > 0:
        dec len
        buf[len] = '\0'
        if echo:
          write("\b \b")

      continue

    if ch < ' ' or ch > '~':
      continue

    if len < LoginLineMax - 1:
      buf[len] = ch
      inc len
      buf[len] = '\0'
      if echo:
        writeChar(ch)
