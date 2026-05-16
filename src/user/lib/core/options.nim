import ../../../lib/types
import ./args
import ./strutils

const
  OptionFlagCap = 128

type
  OptionSpec* {.bycopy.} = object
    short*: char
    long*: cstring

  ParsedOptions* = object
    flags: array[OptionFlagCap, bool]
    positional*: array[UserArgMax, cstring]
    positionalCount*: U32
    help*: bool


proc clearParsedOptions(parsed: var ParsedOptions) =
  var i = 0
  while i < OptionFlagCap:
    parsed.flags[i] = false
    inc i

  i = 0
  while i < UserArgMax:
    parsed.positional[i] = nil
    inc i

  parsed.positionalCount = 0
  parsed.help = false


proc findShort(specs: openArray[OptionSpec], ch: char): int =
  var i = 0
  while i < len(specs):
    if specs[i].short == ch:
      return i
    inc i

  -1


proc findLong(specs: openArray[OptionSpec], name: cstring): int =
  var i = 0
  while i < len(specs):
    if specs[i].long != nil and streq(specs[i].long, name):
      return i
    inc i

  -1


proc setFlag(parsed: var ParsedOptions, ch: char): bool =
  let idx = ord(ch)
  if idx < 0 or idx >= OptionFlagCap:
    return false

  parsed.flags[idx] = true
  true


proc addPositional(parsed: var ParsedOptions, value: cstring): bool =
  if parsed.positionalCount >= U32(UserArgMax):
    return false

  parsed.positional[parsed.positionalCount] = value
  inc parsed.positionalCount
  true


proc hasOption*(parsed: ParsedOptions, ch: char): bool =
  let idx = ord(ch)
  idx >= 0 and idx < OptionFlagCap and parsed.flags[idx]


proc positionalAt*(parsed: var ParsedOptions, index: U32): cstring =
  if index >= parsed.positionalCount:
    return nil

  parsed.positional[index]


proc parseOptions*(args: var UserArgs, specs: openArray[OptionSpec],
                   parsed: var ParsedOptions): bool =
  clearParsedOptions(parsed)

  var positionalOnly = false
  var i = U32(0)
  while i < args.argc:
    let item = argAt(args, i)

    if positionalOnly or item[0] != '-':
      if not addPositional(parsed, item):
        return false
      inc i
      continue

    if item[1] == '\0':
      if not addPositional(parsed, item):
        return false
      inc i
      continue

    if item[1] == '-':
      if item[2] == '\0':
        positionalOnly = true
        inc i
        continue

      let longName = cast[cstring](unsafeAddr item[2])
      if streq(longName, "help"):
        parsed.help = true
        inc i
        continue

      let specIndex = findLong(specs, longName)
      if specIndex < 0:
        return false
      if not setFlag(parsed, specs[specIndex].short):
        return false

      inc i
      continue

    var pos = U32(1)
    while item[pos] != '\0':
      let specIndex = findShort(specs, item[pos])
      if specIndex < 0:
        return false
      if not setFlag(parsed, item[pos]):
        return false
      inc pos

    inc i

  true
