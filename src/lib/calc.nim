import ./types

proc minU64*(a, b: U64): U64 =
  if a < b:
    a
  else:
    b


proc saturatingAddU64*(a, b: U64): U64 =
  if high(U64) - a < b:
    high(U64)
  else:
    a + b


proc saturatingIncU64*(value: var U64) =
  if value < high(U64):
    inc value
