import ../../../lib/rkx
import ../../../lib/syscall_caps
import ../../lib/core/args
import ../../lib/core/io
import ../../lib/core/pathutils
import ../../lib/core/strutils
import ../../lib/core/syscall

const
  PathBufSize = 128

var
  parsedArgs: UserArgs
  pathBuf: array[PathBufSize, char]
  header: RkxHeader


proc printUsage() =
  write("usage: rkxinfo <app|/bin/app>\n")


proc clearPathBuf() =
  var i = 0
  while i < PathBufSize:
    pathBuf[i] = '\0'
    inc i


proc appendPath(s: cstring, pos: var U32): bool =
  var i = U32(0)
  while s[i] != '\0':
    if pos + U32(1) >= U32(PathBufSize):
      return false
    pathBuf[pos] = s[i]
    inc pos
    inc i
  pathBuf[pos] = '\0'
  true


proc buildBinPath(name: cstring): cstring =
  clearPathBuf()
  var pos = U32(0)
  if not appendPath(cstring("/bin/"), pos):
    return nil
  if not appendPath(name, pos):
    return nil

  cast[cstring](addr pathBuf[0])


proc inputPath(arg: cstring): cstring =
  if arg == nil or arg[0] == '\0':
    return nil
  if arg[0] == '/':
    return resolvePath(arg)

  buildBinPath(arg)


proc writeField(name: cstring, value: U64) =
  write(name)
  write(": ")
  writeUnsigned(value)
  write("\n")


proc writeHexField(name: cstring, value: U64) =
  write(name)
  write(": ")
  writeHexValue(value)
  write("\n")


proc writeCapName(mask: U32, bit: U32, name: cstring, first: var bool) =
  if (mask and bit) == 0:
    return
  if not first:
    write(",")
  write(name)
  first = false


proc writeCaps(mask: U32) =
  writeHex32Value(mask)
  write(" (")
  if mask == SysCapNone:
    write("none")
  else:
    var first = true
    writeCapName(mask, SysCapServiceManager, SysCapServiceManagerName, first)
    writeCapName(mask, SysCapRawFs, SysCapRawFsName, first)
    writeCapName(mask, SysCapRawBlock, SysCapRawBlockName, first)
    writeCapName(mask, SysCapRawNet, SysCapRawNetName, first)
    writeCapName(mask, SysCapProcessList, SysCapProcessListName, first)
    writeCapName(mask, SysCapProcessKill, SysCapProcessKillName, first)
    writeCapName(mask, SysCapTrace, SysCapTraceName, first)
    writeCapName(mask, SysCapShutdown, SysCapShutdownName, first)
    let unknown = mask and not SysCapAllKnown
    if unknown != SysCapNone:
      if not first:
        write(",")
      write("unknown:")
      writeHex32Value(unknown)
  write(")")


proc writeSegment(name: cstring, va, off, fileSize, memSize: U64) =
  write(name)
  write(": va=")
  writeHexValue(va)
  write(" off=")
  writeUnsigned(off)
  write(" file=")
  writeUnsigned(fileSize)
  write(" mem=")
  writeUnsigned(memSize)
  write("\n")


proc printHeader(path: cstring) =
  write("path: ")
  write(path)
  write("\n")
  write("magic: RKX1\n")
  writeField("version", U64(header.version))
  writeField("header_size", U64(header.headerSize))
  writeHexField("entry", header.entryVa)
  write("capability_mask: ")
  writeCaps(header.capabilityMask)
  write("\n")

  writeSegment("text", header.textVa, header.textOff, header.textFileSize, header.textMemSize)
  writeSegment("rodata", header.rodataVa, header.rodataOff, header.rodataFileSize, header.rodataMemSize)
  writeSegment("data", header.dataVa, header.dataOff, header.dataFileSize, header.dataMemSize)
  write("bss: va=")
  writeHexValue(header.bssVa)
  write(" mem=")
  writeUnsigned(header.bssMemSize)
  write("\n")
  writeField("stack_pages", U64(header.stackPages))
  writeHexField("flags", U64(header.flags))


proc fail(msg: cstring) {.noreturn.} =
  write("rkxinfo: ")
  write(msg)
  write("\n")
  sysExit(1)


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


proc user_start*(arg: cstring) {.exportc, cdecl, noreturn.} =
  if not parseUserArgs(arg, parsedArgs):
    printUsage()
    sysExit(1)

  if parsedArgs.argc == 1 and cstringEq(argAt(parsedArgs, 0), "--help"):
    printUsage()
    sysExit(0)

  if parsedArgs.argc != 1:
    printUsage()
    sysExit(1)

  let path = inputPath(argAt(parsedArgs, 0))
  if path == nil:
    fail(cstring("path too long"))

  readHeader(path)
  printHeader(path)
  sysExit(0)
