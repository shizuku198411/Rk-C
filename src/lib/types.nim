type
  U8* = uint8
  U16* = uint16
  U32* = uint32
  U64* = uint64
  CSize* = uint
  Size* = uint64
  PAddr* = uint64
  VAddr* = uint64

const
  NilPAddr* = PAddr(0)
  PageSize* = U64(4096)

func alignUp*(value, align: U64): U64 {.inline.} =
  (value + align - 1'u64) and not (align - 1'u64)

func alignDown*(value, align: U64): U64 {.inline.} =
  value and not (align - 1'u64)

func isAligned*(value, align: U64): bool {.inline.} =
  (value and (align - 1'u64)) == 0
