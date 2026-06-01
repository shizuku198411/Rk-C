## Counts lines, words, and bytes for one file.
import ../../lib/core/io
import ../../lib/core/args
import ../../lib/core/app
import ../../lib/core/syscall
import ../../lib/core/pathutils


const BufSize = 4096


var
  parsedArgs: UserArgs
  buffer: array[BufSize, char]
  pathBuf: array[PathMax, char]


## Prints wc usage information.
proc printUsage() =
  write("usage: wc <path>\n")


## Returns true for word-separating horizontal whitespace.
proc isSpace(c: char): bool =
  if c == ' ' or c == '\t' or c == '\r':
    return true
  false


## Returns true for newline characters counted as lines.
proc isNewLine(c: char): bool =
  if c == '\n':
    return true
  false


## Prints the final wc counters and source path.
proc printFileContents(ln, wc, size: U64, path: cstring) =
  writeUnsigned(ln)
  write(" ")
  writeUnsigned(wc)
  write(" ")
  writeUnsigned(size)
  write(" ")
  write(path)
  write("\n")


## Reads a file, computes counters, and prints them.
proc user_start*(arg: cstring) {.exportc, cdecl, noreturn.} =
  parseArgsOrExit(arg, parsedArgs, printUsage)
  exitIfHelp(parsedArgs, printUsage)
  requireArgc(parsedArgs, U32(1), printUsage)
  
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
