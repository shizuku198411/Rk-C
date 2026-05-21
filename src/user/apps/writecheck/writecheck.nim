## Validates write-file modes for create, append, overwrite, and denial cases.
import ../../lib/core/io
import ../../lib/core/strutils
import ../../lib/core/syscall


const
  MainPath = cstring"/tmp/writecheck_main"
  MissingPath = cstring"/tmp/writecheck_missing"
  CreateAppendPath = cstring"/tmp/writecheck_create_append"

var buf: array[64, char]


## Prints writecheck usage information.
proc printUsage() =
  write("usage: writecheck\n")


## Returns whether a file exactly matches the expected string.
proc expectFile(path, expected: cstring): bool =
  let n = sysReadFile(path, addr buf[0], U64(63))
  if n < 0:
    return false
  buf[n] = '\0'
  cstringEq(cast[cstring](addr buf[0]), expected)


## Requires a write operation to succeed.
proc mustWrite(path, text: cstring, flags: U32, label: cstring) =
  if sysWriteFileMode(path, cast[pointer](text), cstrlen(text), flags) != 0:
    write("writecheck: ")
    write(label)
    write(" failed\n")
    sysExit(1)


## Requires a write operation to be denied.
proc mustDeny(path, text: cstring, flags: U32, label: cstring) =
  if sysWriteFileMode(path, cast[pointer](text), cstrlen(text), flags) == 0:
    write("writecheck: ")
    write(label)
    write(" unexpectedly succeeded\n")
    sysExit(1)


## Requires a file to contain the expected value and prints success.
proc requireFile(path, expected, label: cstring) =
  if not expectFile(path, expected):
    write("writecheck: ")
    write(label)
    write(" mismatch\n")
    sysExit(1)
  write("writecheck: ")
  write(label)
  write(" ok\n")


## Runs the write-mode validation sequence.
proc user_start*(arg: cstring) {.exportc, cdecl, noreturn.} =
  if cstringEq(arg, cstring"--help"):
    printUsage()
    sysExit(0)

  discard sysUnlink(MainPath)
  discard sysUnlink(MissingPath)
  discard sysUnlink(CreateAppendPath)

  mustWrite(MainPath, cstring"one", SysFsWriteCreate or SysFsWriteOverwrite, cstring"create overwrite")
  requireFile(MainPath, cstring"one", cstring"create overwrite")

  mustWrite(MainPath, cstring"two", SysFsWriteAppend, cstring"append existing")
  requireFile(MainPath, cstring"onetwo", cstring"append existing")

  mustWrite(MainPath, cstring"x", SysFsWriteOverwrite, cstring"overwrite existing")
  requireFile(MainPath, cstring"x", cstring"overwrite existing")

  mustDeny(MissingPath, cstring"nope", SysFsWriteAppend, cstring"append missing denied")
  write("writecheck: append missing denied ok\n")

  mustWrite(CreateAppendPath, cstring"new", SysFsWriteCreate or SysFsWriteAppend, cstring"create append")
  requireFile(CreateAppendPath, cstring"new", cstring"create append")

  mustDeny(MainPath, cstring"bad", SysFsWriteOverwrite or SysFsWriteAppend, cstring"invalid flags denied")
  write("writecheck: invalid flags denied ok\n")

  discard sysUnlink(MainPath)
  discard sysUnlink(CreateAppendPath)

  write("writecheck: ok\n")
  sysExit(0)
