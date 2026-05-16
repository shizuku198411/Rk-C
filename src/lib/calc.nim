import ./types

proc minU64*(a, b: U64): U64 =
  if a < b:
    a
  else:
    b
