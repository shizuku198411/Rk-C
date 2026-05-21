## Parses and writes shadow password records with PBKDF2 metadata.
import ./syscall
import ./strutils


const
  ShadowNameMax* = U32(32)
  ShadowSaltLen* = U32(16)
  ShadowHashLen* = U32(32)
  ShadowSaltHexLen* = U32(ShadowSaltLen * U32(2))
  ShadowHashHexLen* = U32(ShadowHashLen * U32(2))
  ShadowLineMax* = U32(160)
  ShadowDefaultIterations* = U32(128)


type
  ShadowEntry* = object
    name*: array[ShadowNameMax, char]
    iterations*: U32
    salt*: array[ShadowSaltLen, U8]
    hash*: array[ShadowHashLen, U8]


## Resets a shadow entry to empty fields and zeroed secret material.
proc clearShadowEntry*(entry: var ShadowEntry) =
  var i = U32(0)
  while i < ShadowNameMax:
    entry.name[i] = '\0'
    inc i

  i = U32(0)
  while i < ShadowSaltLen:
    entry.salt[i] = U8(0)
    inc i

  i = U32(0)
  while i < ShadowHashLen:
    entry.hash[i] = U8(0)
    inc i

  entry.iterations = U32(0)


## Copies one delimited shadow field into a fixed-size destination buffer.
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


## Trims CR/LF bytes from the end of a shadow line field.
proc trimLineEnd(line: cstring, startPos, pos: U32): U32 =
  var endPos = pos
  while endPos > startPos and
      (line[endPos - U32(1)] == char(10) or line[endPos - U32(1)] == char(13)):
    dec endPos

  endPos


## Converts one hexadecimal character to its numeric nibble value.
proc hexValue(ch: char, outValue: var U8): bool =
  if ch >= '0' and ch <= '9':
    outValue = U8(ord(ch) - ord('0'))
    return true

  if ch >= 'a' and ch <= 'f':
    outValue = U8(10 + ord(ch) - ord('a'))
    return true

  if ch >= 'A' and ch <= 'F':
    outValue = U8(10 + ord(ch) - ord('A'))
    return true

  false


## Parses a fixed-width hexadecimal byte sequence into raw bytes.
proc parseHexBytes(line: cstring, startPos, endPos: U32, outBuf: pointer, outLen: U32): bool =
  if endPos - startPos != outLen * U32(2):
    return false

  let dst = cast[ptr UncheckedArray[U8]](outBuf)
  var i = U32(0)
  while i < outLen:
    var hi = U8(0)
    var lo = U8(0)
    if not hexValue(line[startPos + i * U32(2)], hi):
      return false
    if not hexValue(line[startPos + i * U32(2) + U32(1)], lo):
      return false

    dst[i] = (hi shl U8(4)) or lo
    inc i

  true


## Parses a delimited shadow field as an unsigned 32-bit integer.
proc parseFieldU32(line: cstring, startPos, endPos: U32, value: var U32): bool =
  var buf: array[16, char]
  if not copyField(buf, line, startPos, endPos):
    return false

  parseU32(cast[cstring](addr buf[0]), value)


## Parses one shadow database line into a ShadowEntry.
proc parseShadowLine*(line: cstring, entry: var ShadowEntry): bool =
  clearShadowEntry(entry)

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

  if fieldCount != U32(5):
    return false

  let nameStart = fields[0]
  let algoStart = fields[1]
  let iterStart = fields[2]
  let saltStart = fields[3]
  let hashStart = fields[4]
  let nameEnd = algoStart - U32(1)
  let algoEnd = iterStart - U32(1)
  let iterEnd = saltStart - U32(1)
  let saltEnd = hashStart - U32(1)
  let hashEnd = trimLineEnd(line, hashStart, pos)

  if nameEnd == nameStart or not copyField(entry.name, line, nameStart, nameEnd):
    return false

  if not cstringEq(cast[cstring](addr line[algoStart]), cstring"pbkdf2-sha256"):
    var algoBuf: array[24, char]
    if not copyField(algoBuf, line, algoStart, algoEnd):
      return false
    if not cstringEq(cast[cstring](addr algoBuf[0]), cstring"pbkdf2-sha256"):
      return false

  if not parseFieldU32(line, iterStart, iterEnd, entry.iterations):
    return false

  if not parseHexBytes(line, saltStart, saltEnd, addr entry.salt[0], ShadowSaltLen):
    return false

  parseHexBytes(line, hashStart, hashEnd, addr entry.hash[0], ShadowHashLen)


## Writes one ShadowEntry as a shadow database line.
proc writeShadowLine*(dst: pointer, capacity: U32, entry: ShadowEntry): U32 =
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

  template appendHexByte(value: U8) =
    let table = cstring"0123456789abcdef"
    appendChar(table[(value shr U8(4)) and U8(0xf)])
    appendChar(table[value and U8(0xf)])

  appendCString(cast[cstring](addr entry.name[0]))
  appendChar(':')
  appendCString(cstring"pbkdf2-sha256")
  appendChar(':')
  appendU32(entry.iterations)
  appendChar(':')

  var i = U32(0)
  while i < ShadowSaltLen:
    appendHexByte(entry.salt[i])
    inc i

  appendChar(':')
  i = U32(0)
  while i < ShadowHashLen:
    appendHexByte(entry.hash[i])
    inc i

  appendChar('\n')
  pos
