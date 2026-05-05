proc rawoutput(msg: string) =
  discard msg


proc panic(msg: string) {.noreturn.} =
  rawoutput(msg)
  while true:
    asm "wfi"
