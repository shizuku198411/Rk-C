import ../../lib/core/io
import ../../lib/core/args
import ../../lib/core/syscall
import ../../lib/core/strutils


const BufSize = 4096


var
  parsedArgs: UserArgs
  buffer: array[BufSize, char]


proc printUsage() =
  write("usage: wc <path>\n")


proc isSpace(c: char): bool =
  if c == ' ' or c == '\t':
    return true
  false


proc isNewLine(c: char): bool =
  if c == '\n':
    return true
  false


proc isTerminate(c: char): bool =
  if c == '\0':
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
    path = argAt(parsedArgs, 0)
    fileSize = sysReadFile(path, addr buffer[0], U64(BufSize))
  if fileSize < 0:
    write("failed to read file\n")
    sysExit(1)
  
  var
    lineNum: U64 = 0
    wordNum: U64 = 0

  if fileSize == 0:
    printFileContents(0, 0, 0, path)
    sysExit(0)
  inc lineNum

  var i = I32(0)
  while i <= fileSize:
    if isSpace(buffer[i]):
      inc wordNum
    elif isNewLine(buffer[i]):
      inc wordNum
      inc lineNum
    elif isTerminate(buffer[i]):
      inc wordNum
    inc i
  
  printFileContents(lineNum, wordNum, U64(fileSize), path)
  sysExit(0)
