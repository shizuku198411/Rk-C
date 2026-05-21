## Parses raw user app argument strings into argv-style arrays.
import ../../../lib/types
import ./strutils

const
  UserArgMax* = 16
  UserArgLenMax* = 96

type
  UserArgs* = object
    argc*: U32
    argv*: array[UserArgMax, cstring]
    storage: array[UserArgMax, array[UserArgLenMax, char]]


## Clears args.
proc clearArgs(args: var UserArgs) =
  args.argc = 0

  var i = 0
  while i < UserArgMax:
    args.argv[i] = nil

    var j = 0
    while j < UserArgLenMax:
      args.storage[i][j] = '\0'
      inc j

    inc i


## Parses user args.
proc parseUserArgs*(arg: cstring, args: var UserArgs): bool =
  clearArgs(args)

  if isEmpty(arg):
    return true

  var pos = U32(0)
  while arg[pos] != '\0':
    while isSpace(arg[pos]):
      inc pos

    if arg[pos] == '\0':
      break

    if args.argc >= U32(UserArgMax):
      return false

    let index = args.argc
    var len = U32(0)
    while arg[pos] != '\0' and not isSpace(arg[pos]):
      if len + 1 >= U32(UserArgLenMax):
        return false

      args.storage[index][len] = arg[pos]
      inc len
      inc pos

    args.storage[index][len] = '\0'
    args.argv[index] = cast[cstring](addr args.storage[index][0])
    inc args.argc

  true


## Implements the arg at helper.
proc argAt*(args: var UserArgs, index: U32): cstring =
  if index >= args.argc:
    return nil

  args.argv[index]


## Returns whether arg is present.
proc hasArg*(args: var UserArgs, value: cstring): bool =
  var i = U32(0)
  while i < args.argc:
    if cstringEq(args.argv[i], value):
      return true

    inc i

  false


## Copies argv tail.
proc copyArgvTail*(args: var UserArgs, start: U32, dst: pointer, dstLen: U32): bool =
  let outBuf = cast[ptr UncheckedArray[char]](dst)
  var outPos = U32(0)
  var i = start

  if dstLen == 0:
    return false

  while i < args.argc:
    if i > start:
      if outPos + 1 >= dstLen:
        return false

      outBuf[outPos] = ' '
      inc outPos

    let item = args.argv[i]
    var j = U32(0)
    while item[j] != '\0':
      if outPos + 1 >= dstLen:
        return false

      outBuf[outPos] = item[j]
      inc outPos
      inc j

    inc i

  outBuf[outPos] = '\0'
  true
