import types

const
  SysProcessNameMax* = 32

  SysProcessUnused* = U32(0)
  SysProcessRunnable* = U32(1)
  SysProcessRunning* = U32(2)
  SysProcessSleeping* = U32(3)
  SysProcessZombie* = U32(4)

type
  SysProcessInfo* {.packed.} = object
    pid*: I32
    ppid*: I32
    state*: U32
    isUser*: U32
    exePath*: array[SysProcessNameMax, char]

  SysDateTime* {.packed.} = object
    year*: U32
    month*: U32
    day*: U32
    hour*: U32
    minute*: U32
    second*: U32
