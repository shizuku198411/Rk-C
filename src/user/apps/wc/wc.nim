import ../../lib/core/io
import ../../lib/core/args
import ../../lib/core/syscall
import ../../lib/core/pathutils
import ../../lib/core/strutils


const BufSize = 4096


var
  parsedArgs: UserArgs
  buffer: array[BufSize, char]
  pathBuf: array[PathMax, char]


proc printUsage() =
  write("usage: wc <path>\n")


proc isSpace(c: char): bool =
  if c == ' ' or c == '\t' or c == '\r':
    return true
  false


proc isNewLine(c: char): bool =
  if c == '\n':
    return true
  false


proc printFileContents(ln, wc, size: U64, path: cstring) =
  writeUnsigned(ln)
  write(" ")
  writeUnsigned(wc)
  write(" ")
  writeUnsigned(size)
  write(" ")
  write(path)
  write("\n")


proc user_start*(arg: cstring) {.exportc, cdecl, noreturn.} =
  if not parseUserArgs(arg, parsedArgs):
    printUsage()
    sysExit(1)
  
  if parsedArgs.argc == 1 and cstringEq(argAt(parsedArgs, 0), "--help"):
    printUsage()
    sysExit(0)
  
  if parsedArgs.argc == 0:
    printUsage()
    sysExit(1)
  
  let
    path = resolvePathInto(argAt(parsedArgs, 0), pathBuf)
  if path == nil:
    write("wc: path too long\n")
    sysExit(1)

  let
    fileSize = sysReadFile(path, addr buffer[0], U64(BufSize))
  if fileSize < 0:
    write("failed to read file\n")
    sysExit(1)
  
  if fileSize == 0:
    printFileContents(0, 0, 0, path)
    sysExit(0)
  
  var
    lineNum: U64 = 1
    wordNum: U64 = 0

  var inWord = false

  var i = I32(0)
  while i < fileSize:
    if isNewLine(buffer[i]):
      if inWord:
        inc wordNum
        inWord = false
      inc lineNum
    elif isSpace(buffer[i]):
      if inWord:
        inc wordNum
        inWord = false
    else:
      inWord = true
    inc i

  if inWord:
    inc wordNum
  
  printFileContents(lineNum, wordNum, U64(fileSize), path)
  sysExit(0)
