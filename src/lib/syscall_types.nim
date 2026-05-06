import types

const
  SysProcessNameMax* = 32
  SysProcessCwdMax* = 64
  SysIpcMessageMax* = 128
  SysIpcQueueCap* = 4
  SysFsPathMax* = 128
  SysFsDataMax* = 4096
  SysBlockDataSize* = 512

  SysFsOpLs* = U32(1)
  SysFsOpMkdir* = U32(2)
  SysFsOpUnlink* = U32(3)
  SysFsOpRmdir* = U32(4)
  SysFsOpReadFile* = U32(5)
  SysFsOpWriteFile* = U32(6)
  SysBlockOpRead* = U32(1)
  SysBlockOpWrite* = U32(2)
  SysIpcOpText* = U32(0)
  SysIpcOpSvcRestart* = U32(1)
  SysServiceKindBlock* = U32(0)
  SysServiceKindFs* = U32(1)
  SysServiceKindManager* = U32(2)
  SysServiceNameMax* = U32(16)

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

  SysBitmapInfo* {.packed.} = object
    total*: U64
    used*: U64
    free*: U64

  SysIpcMessage* {.packed.} = object
    senderPid*: I32
    len*: U32
    data*: array[SysIpcMessageMax, char]

  SysIpcPacket* {.packed.} = object
    senderPid*: I32
    op*: U32
    arg0*: U64
    arg1*: U64
    len*: U32
    data*: array[SysIpcMessageMax, char]

  SysFsRequest* {.packed.} = object
    id*: U64
    op*: U32
    path*: array[SysFsPathMax, char]
    size*: U64
    capacity*: U64
    data*: array[SysFsDataMax, U8]

  SysFsResponse* {.packed.} = object
    id*: U64
    result*: I32
    size*: U64
    data*: array[SysFsDataMax, U8]

  SysBlockRequest* {.packed.} = object
    id*: U64
    op*: U32
    blockIndex*: U64
    data*: array[SysBlockDataSize, U8]

  SysBlockResponse* {.packed.} = object
    id*: U64
    result*: I32
    data*: array[SysBlockDataSize, U8]
  
  SysServiceInfo* {.packed.} = object
    kind*: U32
    pid*: I32
    registered*: U32
    available*: U32
    name*: array[SysServiceNameMax, char]
