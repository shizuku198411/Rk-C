## Prints the current system date and time.
import ../../lib/core/io
import ../../lib/core/args
import ../../lib/core/app
import ../../lib/core/syscall

var parsedArgs: UserArgs


## Writes a two-digit decimal value with leading zero support.
proc write2(value: U32) =
  writeChar(char(ord('0') + int((value div 10) mod 10)))
  writeChar(char(ord('0') + int(value mod 10)))


## Writes a four-digit decimal value with leading zero support.
proc write4(value: U32) =
  writeChar(char(ord('0') + int((value div 1000) mod 10)))
  writeChar(char(ord('0') + int((value div 100) mod 10)))
  writeChar(char(ord('0') + int((value div 10) mod 10)))
  writeChar(char(ord('0') + int(value mod 10)))


## Formats and prints a SysDateTime value.
proc printDateTime(dt: ptr SysDateTime) =
  write4(dt.year)
  write("/")
  write2(dt.month)
  write("/")
  write2(dt.day)
  write(" ")
  write2(dt.hour)
  write(":")
  write2(dt.minute)
  write(":")
  write2(dt.second)
  write("\n")


## Prints date usage information.
proc printUsage() =
  write("usage: date\n")


## Requests the current date from the kernel and prints it.
proc user_start*(arg: cstring) {.exportc, cdecl, noreturn.} =
  parseArgsOrExit(arg, parsedArgs, printUsage)
  exitIfHelp(parsedArgs, printUsage)
  requireArgc(parsedArgs, U32(0), printUsage)

  var dt: SysDateTime
  if sysGetDateTime(addr dt) != 0:
    write("date: failed\n")
    sysExit(1)

  printDateTime(addr dt)
  sysExit(0)
