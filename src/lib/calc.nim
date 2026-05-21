## Provides small shared arithmetic helpers.
import ./types

## Returns the smaller u64.
proc minU64*(a, b: U64): U64 =
  if a < b:
    a
  else:
    b


## Performs saturating add u64.
proc saturatingAddU64*(a, b: U64): U64 =
  if high(U64) - a < b:
    high(U64)
  else:
    a + b


## Performs saturating inc u64.
proc saturatingIncU64*(value: var U64) =
  if value < high(U64):
    inc value
