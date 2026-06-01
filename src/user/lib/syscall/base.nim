## Provides shared types and the raw syscall entry point for userland wrappers.
import ../../../lib/syscall_types

export syscall_types

type
  U8* = uint8
  U16* = uint16
  U32* = uint32
  U64* = uint64
  I32* = int32
  I64* = int64


## Imports the assembly raw syscall entry point.
proc rawSyscall3*(num, arg0, arg1, arg2: U64): U64 {.importc: "user_raw_syscall3", cdecl.}


## Stops execution when a noreturn syscall unexpectedly returns.
proc halt*() {.noreturn.} =
  while true:
    asm "wfi"
