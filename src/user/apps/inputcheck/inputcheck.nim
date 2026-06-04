## Validates a full-size burst read from standard input.
import ../../lib/core/app
import ../../lib/core/args
import ../../lib/core/io
import ../../lib/core/syscall


const
  BurstSize = U64(4096)
  ChunkSize = U64(256)
  ExpectedByte = U8('x')


var
  parsedArgs: UserArgs
  inputBuf: array[ChunkSize, U8]


## Prints inputcheck usage information.
proc printUsage() =
  write("usage: inputcheck\n")


## Prints an inputcheck failure and exits.
proc fail(msg: cstring) {.noreturn.} =
  write("inputcheck: FAIL ")
  write(msg)
  write("\n")
  sysExit(1)


## Reads and validates one fixed-size burst from standard input.
proc runCheck() =
  var received = U64(0)
  while received < BurstSize:
    let remaining = BurstSize - received
    let requestLen =
      if remaining < ChunkSize:
        remaining
      else:
        ChunkSize

    let readLen = sysReadFd(I32(0), addr inputBuf[0], requestLen)
    if readLen <= I32(0):
      fail(cstring("read"))

    var i = U64(0)
    while i < U64(readLen):
      if inputBuf[i] != ExpectedByte:
        fail(cstring("content"))
      inc i

    received += U64(readLen)

  write("inputcheck: 4096-byte burst ok\n")
  sysExit(0)


## Parses inputcheck arguments and runs the burst validation.
proc user_start*(arg: cstring) {.exportc, cdecl, noreturn.} =
  parseArgsOrExit(arg, parsedArgs, printUsage)
  exitIfHelp(parsedArgs, printUsage)
  requireArgc(parsedArgs, U32(0), printUsage)

  runCheck()
