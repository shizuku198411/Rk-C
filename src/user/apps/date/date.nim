import ../../lib/io
import ../../lib/syscall

proc write2(value: U32) =
  writeChar(char(ord('0') + int((value div 10) mod 10)))
  writeChar(char(ord('0') + int(value mod 10)))

proc write4(value: U32) =
  writeChar(char(ord('0') + int((value div 1000) mod 10)))
  writeChar(char(ord('0') + int((value div 100) mod 10)))
  writeChar(char(ord('0') + int((value div 10) mod 10)))
  writeChar(char(ord('0') + int(value mod 10)))

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

proc user_start*(arg: cstring) {.exportc, cdecl, noreturn.} =
  discard arg

  var dt: SysDateTime
  if sysGetDateTime(addr dt) != 0:
    write("date: failed\n")
    sysExit(1)

  printDateTime(addr dt)
  sysExit(0)
