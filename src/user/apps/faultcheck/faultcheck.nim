import ../../lib/core/args
import ../../lib/core/io
import ../../lib/core/strutils
import ../../lib/core/syscall


type
  CodeFn = proc() {.cdecl.}


var parsedArgs: UserArgs


{.emit: """
extern void user_entry(void);

void faultcheck_write_user_text(void) {
  *((volatile unsigned char *)&user_entry) = 0;
}
""".}


proc writeUserText() {.importc: "faultcheck_write_user_text", cdecl.}


proc printUsage() =
  write("usage: faultcheck <bad-cstring|write-text|exec-stack>\n")


proc badCString() =
  let bad = cast[cstring](U64(0x0000004000000000'u64))
  let fd = sysOpen(bad, SysOpenRead)
  if fd < 0:
    write("bad-cstring: rejected\n")
    sysExit(0)

  discard sysClose(fd)
  write("bad-cstring: unexpectedly accepted\n")
  sysExit(1)


proc writeText() =
  write("write-text: touching text\n")
  writeUserText()
  write("write-text: unexpectedly returned\n")
  sysExit(1)


proc execStack() =
  var code: array[8, U8]

  # RISC-V compressed ret: c.jr ra
  code[0] = U8(0x82)
  code[1] = U8(0x80)

  write("exec-stack: jumping to stack\n")
  let fn = cast[CodeFn](addr code[0])
  fn()
  write("exec-stack: unexpectedly returned\n")
  sysExit(1)


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

  let mode = argAt(parsedArgs, 0)
  if cstringEq(mode, "bad-cstring"):
    badCString()
  elif cstringEq(mode, "write-text"):
    writeText()
  elif cstringEq(mode, "exec-stack"):
    execStack()

  printUsage()
  sysExit(1)
