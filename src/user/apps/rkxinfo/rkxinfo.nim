## Prints metadata from an RKX executable image.
{.warning[UnusedImport]: off.}

import ../../../lib/rkx
import ../../lib/runtime/orc_osalloc
import ../../lib/core/args
import ../../lib/core/app
import ../../lib/core/cap_names
import ../../lib/core/io
import ../../lib/core/path_buffer
import ../../lib/core/pathutils
import ../../lib/core/strutils
import ../../lib/core/syscall

const
  RkxInfoPathMax = 128

var
  parsedArgs: UserArgs
  header: RkxHeader
  trustEntries: array[SysRkxTrustMaxEntries, SysRkxTrustInfo]

  ## ORC-managed text used for output rendering.
  renderedText: string = ""

  ## ORC-managed path text used for formatting/debug display.
  pathText: string = ""

  ## Stable fixed buffer used for syscall path arguments.
  ##
  ## Do not pass pathText.cstring directly to sysOpen().  Keep a fixed
  ## syscall-facing path buffer so the kernel sees a stable user pointer.
  syscallPathBuf: array[RkxInfoPathMax, char]


## Prints rkxinfo usage information.
proc printUsage() =
  write("usage: rkxinfo <app|/bin/app>\n")


## Returns the syscall-facing path cstring.
proc syscallPathCString(): cstring =
  cast[cstring](addr syscallPathBuf[0])


## Copies a cstring into ORC-managed path text.
proc setPathText(src: cstring): bool =
  pathText = ""

  if src == nil:
    return false

  var i = 0
  while src[i] != '\0':
    pathText.add(src[i])
    inc i

  true


## Sets both display path text and syscall path buffer.
proc setResolvedPath(src: cstring): cstring =
  if src == nil:
    return nil

  if not setPathText(src):
    return nil

  if not copyCStringInto(
    cast[ptr UncheckedArray[char]](addr syscallPathBuf[0]),
    RkxInfoPathMax,
    src,
  ):
    return nil

  syscallPathCString()


## Resolves an absolute path or converts an app name to /bin/<name>.
proc inputPath(arg: cstring): cstring =
  if arg == nil or arg[0] == '\0':
    return nil

  if arg[0] == '/':
    return setResolvedPath(resolvePath(arg))

  pathText = ""
  pathText.add("/bin/")

  var i = 0
  while arg[i] != '\0':
    pathText.add(arg[i])
    inc i

  if not copyCStringInto(
    cast[ptr UncheckedArray[char]](addr syscallPathBuf[0]),
    RkxInfoPathMax,
    pathText.cstring,
  ):
    return nil

  syscallPathCString()


## Clears the ORC-owned output buffer.
proc clearRenderedText() =
  renderedText = ""


## Appends a cstring to the ORC-owned output buffer.
proc appendText(s: cstring) =
  if s == nil:
    return

  var i = 0
  while s[i] != '\0':
    renderedText.add(s[i])
    inc i


## Appends an ORC-managed string to the ORC-owned output buffer.
proc appendString(s: string) =
  var i = 0
  while i < s.len:
    renderedText.add(s[i])
    inc i


## Appends one character to the ORC-owned output buffer.
proc appendChar(ch: char) =
  renderedText.add(ch)


## Appends a decimal unsigned integer to the ORC-owned output buffer.
proc appendUnsignedValue(value: U64) =
  var tmp: array[32, char]
  var n = value
  var len = 0

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


## Appends a hexadecimal unsigned integer to the ORC-owned output buffer.
proc appendHexValue(value: U64) =
  appendText(cstring("0x"))

  if value == U64(0):
    appendChar('0')
    return

  var started = false
  var shift = 60

  while shift >= 0:
    let digit = int((value shr U64(shift)) and U64(0xf))

    if digit != 0 or started:
      started = true
      if digit < 10:
        appendChar(char(ord('0') + digit))
      else:
        appendChar(char(ord('a') + digit - 10))

    shift -= 4


## Appends a hexadecimal U32 value to the ORC-owned output buffer.
proc appendHex32Value(value: U32) =
  appendHexValue(U64(value))


## Appends one lower-case hex nibble to the ORC-owned output buffer.
proc appendHexNibble(value: U8) =
  let digit = int(value and U8(0xf))
  if digit < 10:
    appendChar(char(ord('0') + digit))
  else:
    appendChar(char(ord('a') + digit - 10))


## Appends one byte as two lower-case hex characters.
proc appendHexByte(value: U8) =
  appendHexNibble(value shr 4)
  appendHexNibble(value)


## Flushes the ORC-owned output buffer to stdout.
proc flushRenderedText() =
  if renderedText.len == 0:
    return
  discard sysWriteFd(1, addr renderedText[0], U64(renderedText.len))


## Appends one decimal RKX header field.
proc appendField(name: cstring, value: U64) =
  appendText(name)
  appendText(cstring(": "))
  appendUnsignedValue(value)
  appendChar('\n')


## Appends one hexadecimal RKX header field.
proc appendHexField(name: cstring, value: U64) =
  appendText(name)
  appendText(cstring(": "))
  appendHexValue(value)
  appendChar('\n')


## Appends a named capability when the entry bit is present.
proc appendCapName(mask: U32, entry: UserCapabilityNameEntry, first: var bool) =
  if (mask and entry.bit) == 0:
    return

  if not first:
    appendText(cstring(","))

  appendText(entry.name)
  first = false


## Appends the decoded capability mask.
proc appendCaps(mask: U32) =
  appendHex32Value(mask)
  appendText(cstring(" ("))

  if capMaskIsNone(mask):
    appendText(cstring("none"))
  else:
    var first = true

    for entry in UserCapabilityNameEntries:
      appendCapName(mask, entry, first)

    let unknown = unknownCapabilityMask(mask)
    if not capMaskIsNone(unknown):
      if not first:
        appendText(cstring(","))
      appendText(cstring("unknown:"))
      appendHex32Value(unknown)

  appendText(cstring(")"))


## Appends one RKX memory segment descriptor.
proc appendSegment(name: cstring, va, off, fileSize, memSize: U64) =
  appendText(name)
  appendText(cstring(": va="))
  appendHexValue(va)
  appendText(cstring(" off="))
  appendUnsignedValue(off)
  appendText(cstring(" file="))
  appendUnsignedValue(fileSize)
  appendText(cstring(" mem="))
  appendUnsignedValue(memSize)
  appendChar('\n')


## Appends the boot-time trust manifest integrity status for this path.
proc appendIntegrity(path: cstring) =
  let count = sysRkxTrustList(addr trustEntries[0], U64(SysRkxTrustMaxEntries))
  if count < 0:
    appendText(cstring("integrity: unavailable\n"))
    return

  var i = U32(0)
  while i < U32(count) and i < SysRkxTrustMaxEntries:
    if trustEntries[i].used != U32(0) and
        cstringEq(cast[cstring](addr trustEntries[i].path[0]), path):
      appendText(cstring("integrity: "))
      if trustEntries[i].verified != U32(0):
        appendText(cstring("verified"))
      else:
        appendText(cstring("untrusted"))
      appendChar('\n')

      appendText(cstring("trusted_sha256: "))
      var h = U32(0)
      while h < SysRkxTrustHashBytes:
        appendHexByte(trustEntries[i].hash[h])
        inc h
      appendChar('\n')
      return

    inc i

  appendText(cstring("integrity: not_manifested\n"))


## Prints all decoded RKX header fields.
proc printHeader(path: cstring) =
  clearRenderedText()

  appendText(cstring("path: "))

  if pathText.len > 0:
    appendString(pathText)
  else:
    appendText(path)

  appendChar('\n')

  appendText(cstring("magic: RKX1\n"))
  appendField(cstring("version"), U64(header.version))
  appendField(cstring("header_size"), U64(header.headerSize))
  appendHexField(cstring("entry"), header.entryVa)

  appendText(cstring("capability_mask: "))
  appendCaps(header.capabilityMask)
  appendChar('\n')

  appendSegment(
    cstring("text"),
    header.textVa,
    header.textOff,
    header.textFileSize,
    header.textMemSize
  )

  appendSegment(
    cstring("rodata"),
    header.rodataVa,
    header.rodataOff,
    header.rodataFileSize,
    header.rodataMemSize
  )

  appendSegment(
    cstring("data"),
    header.dataVa,
    header.dataOff,
    header.dataFileSize,
    header.dataMemSize
  )

  appendText(cstring("bss: va="))
  appendHexValue(header.bssVa)
  appendText(cstring(" mem="))
  appendUnsignedValue(header.bssMemSize)
  appendChar('\n')

  appendField(cstring("stack_pages"), U64(header.stackPages))

  appendText(cstring("allowed_uids: "))
  if header.allowedUidCount == U32(0):
    appendText(cstring("all"))
  else:
    var i = U32(0)
    while i < header.allowedUidCount and i < U32(RkxAllowedUidMax):
      if i > U32(0):
        appendText(cstring(","))
      appendUnsignedValue(U64(header.allowedUids[i]))
      inc i
  appendChar('\n')

  appendHexField(cstring("flags"), U64(header.flags))
  appendIntegrity(path)

  flushRenderedText()


## Prints an rkxinfo error and exits.
proc fail(msg: cstring) {.noreturn.} =
  write("rkxinfo: ")
  write(msg)
  write("\n")
  sysExit(1)


## Reads and validates the RKX header from disk.
proc readHeader(path: cstring) =
  let fd = sysOpen(path, SysOpenRead)
  if fd < 0:
    fail(cstring("open failed"))

  let readLen = sysReadFd(fd, addr header, U64(sizeof(RkxHeader)))
  discard sysClose(fd)

  if readLen != I32(sizeof(RkxHeader)):
    fail(cstring("short read"))

  if header.magic != RkxMagic:
    fail(cstring("bad magic"))

  if header.version != RkxVersion:
    fail(cstring("unsupported version"))

  if header.headerSize < U32(sizeof(RkxHeader)):
    fail(cstring("bad header size"))


## Parses one target and prints its RKX metadata.
proc user_start*(arg: cstring) {.exportc, cdecl, noreturn.} =
  parseArgsOrExit(arg, parsedArgs, printUsage)
  exitIfHelp(parsedArgs, printUsage)
  requireArgc(parsedArgs, U32(1), printUsage)

  let path = inputPath(argAt(parsedArgs, U32(0)))
  if path == nil:
    fail(cstring("path too long"))

  readHeader(path)
  printHeader(path)
  sysExit(0)
