import ./io
import ./syscall


proc writeSignedI32*(value: I32) =
  if value < 0:
    writeChar('-')
    writeUnsigned(U64(-value))
  else:
    writeUnsigned(U64(value))


proc writeYesNo*(value: U32) =
  if value != 0:
    write("yes")
  else:
    write("no")


proc writePaddedCString*(name: cstring, width: int) =
  var i = 0
  while i < width and name[i] != '\0':
    writeChar(name[i])
    inc i

  while i < width:
    write(" ")
    inc i
