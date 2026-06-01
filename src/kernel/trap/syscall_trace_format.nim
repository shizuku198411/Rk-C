## Provides low-level formatting helpers for syscall trace output.
import ../../lib/types
import ../dev/console
import ../mm/usercopy


const
  traceStrBufSize = 64
  tracePreviewBufSize = 48

var
  traceStrBuf: array[traceStrBufSize, char]
  tracePreviewBuf: array[tracePreviewBufSize, U8]


## Prints a user C string argument with a bounded kernel copy.
proc printUserCStringArg*(ptrVal: U64) =
  if ptrVal == 0:
    print("null")
    return

  if copyUserCString(addr traceStrBuf[0], ptrVal, U64(traceStrBufSize)) < 0:
    print("<badptr>")
    return

  print("\"")
  print(cast[cstring](addr traceStrBuf[0]))
  print("\"")


## Prints one byte using escaped text for common control characters.
proc printEscapedByte*(ch: U8) =
  case ch
  of U8('\n'):
    print("\\n")
  of U8('\r'):
    print("\\r")
  of U8('\t'):
    print("\\t")
  of U8('"'):
    print("\\\"")
  of U8('\\'):
    print("\\\\")
  else:
    if ch >= U8(32) and ch < U8(127):
      putChar(char(ch))
    else:
      print(".")


## Prints a bounded preview of a user buffer when verbose tracing is enabled.
proc printBufferPreview*(verbose: bool, ptrVal, len: U64) =
  if not verbose:
    return
  if ptrVal == 0 or len == 0:
    return

  var previewLen = len
  if previewLen > U64(tracePreviewBufSize):
    previewLen = U64(tracePreviewBufSize)

  print(", preview=\"")
  if copyFromUser(addr tracePreviewBuf[0], ptrVal, previewLen) != 0:
    print("<badptr>")
  else:
    var i = U64(0)
    while i < previewLen:
      printEscapedByte(tracePreviewBuf[i])
      inc i
    if len > previewLen:
      print("...")
  print("\"")


## Prints an argument name and equals sign.
proc printName*(name: cstring) =
  print(name)
  print("=")


## Prints a named pointer value.
proc printNamedPtr*(name: cstring, value: U64) =
  printName(name)
  printPtr(value)


## Prints a named unsigned integer value.
proc printNamedU64*(name: cstring, value: U64) =
  printName(name)
  printUnsigned(value)


## Prints a named signed integer value.
proc printNamedI64*(name: cstring, value: U64) =
  printName(name)
  printSigned(int64(value))


## Prints a named user C string value.
proc printNamedCString*(name: cstring, value: U64) =
  printName(name)
  printUserCStringArg(value)


## Prints a named boolean value.
proc printNamedBool*(name: cstring, value: U64) =
  printName(name)
  if value == 0:
    print("false")
  else:
    print("true")


## Prints a trace control command name when known.
proc printTraceCtlCmd*(value: U64) =
  case value
  of 0:
    print("off")
  of 1:
    print("on")
  of 2:
    print("pid")
  of 3:
    print("verbose")
  else:
    printUnsigned(value)


## Prints a named trace control command.
proc printNamedTraceCtlCmd*(name: cstring, value: U64) =
  printName(name)
  printTraceCtlCmd(value)
