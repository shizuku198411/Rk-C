## Defines shared syscall-facing structures and constants.
import types

const
  SysProcessNameMax* = 32
  SysProcessCwdMax* = 64
  SysIpcMessageMax* = 512
  SysIpcQueueCap* = 16
  SysFsPathMax* = 128
  SysFsDataMax* = 4096
  SysFsWriteCreate* = U32(1)
  SysFsWriteOverwrite* = U32(2)
  SysFsWriteAppend* = U32(4)
  SysFsWriteDefault* = SysFsWriteCreate or SysFsWriteOverwrite
  SysFsWriteKnownFlags* = SysFsWriteCreate or SysFsWriteOverwrite or SysFsWriteAppend
  SysFsInfoNameMax* = U32(16)
  SysFsInfoMaxEntries* = U32(4)
  SysBlockDataSize* = 512
  SysNetMacLen* = 6
  SysNetPacketMax* = 1514
  SysKmsgMax* = U32(16384)

  SysFsOpLs* = U32(1)
  SysFsOpMkdir* = U32(2)
  SysFsOpUnlink* = U32(3)
  SysFsOpRmdir* = U32(4)
  SysFsOpReadFile* = U32(5)
  SysFsOpWriteFile* = U32(6)
  SysFsOpFileSize* = U32(7)
  SysFsOpReadRange* = U32(8)
  SysFsOpRename* = U32(9)
  SysFsOpChmod* = U32(10)
  SysFsOpChown* = U32(11)
  SysBlockOpRead* = U32(1)
  SysBlockOpWrite* = U32(2)

  SysIpcOpText* = U32(0)
  SysIpcOpSvcRestart* = U32(1)
  SysIpcOpProcListRequest* = U32(2)
  SysIpcOpProcListResponse* = U32(3)
  SysIpcOpProcListEntry* = U32(4)
  SysIpcOpProcKillRequest* = U32(5)
  SysIpcOpProcKillResponse* = U32(6)
  SysIpcOpNetPingRequest* = U32(7)
  SysIpcOpNetPingResponse* = U32(8)
  SysIpcOpSvcReady* = U32(9)
  SysIpcOpNetUdpSendRequest* = U32(11)
  SysIpcOpNetUdpSendResponse* = U32(12)
  SysIpcOpNetUdpReceiveRequest* = U32(13)
  SysIpcOpNetUdpReceiveResponse* = U32(14)
  SysIpcOpNetTcpConnectRequest* = U32(15)
  SysIpcOpNetTcpConnectResponse* = U32(16)
  SysIpcOpNetTcpSendRequest* = U32(17)
  SysIpcOpNetTcpSendResponse* = U32(18)
  SysIpcOpNetTcpReceiveRequest* = U32(19)
  SysIpcOpNetTcpReceiveResponse* = U32(20)
  SysIpcOpNetTcpCloseRequest* = U32(21)
  SysIpcOpNetTcpCloseResponse* = U32(22)
  SysIpcOpProcFsReadRequest* = U32(23)
  SysIpcOpProcFsReadResponse* = U32(24)
  SysIpcOpProcFsLsRequest* = U32(25)
  SysIpcOpProcFsLsResponse* = U32(26)
  SysIpcOpSvcStatusRequest* = U32(27)
  SysIpcOpSvcStatusResponse* = U32(28)
  SysIpcOpSvcLogsRequest* = U32(29)
  SysIpcOpSvcLogsResponse* = U32(30)
  SysIpcOpSvcStart* = U32(31)
  SysIpcOpSvcStop* = U32(32)
  SysIpcOpSvcCommandResponse* = U32(33)
  SysIpcOpUserResolveNameRequest* = U32(34)
  SysIpcOpUserResolveUidRequest* = U32(35)
  SysIpcOpUserResolveResponse* = U32(36)
  SysIpcOpGroupResolveNameRequest* = U32(37)
  SysIpcOpGroupResolveGidRequest* = U32(38)
  SysIpcOpGroupResolveResponse* = U32(39)
  SysIpcOpUserAuthRequest* = U32(40)
  SysIpcOpUserAuthResponse* = U32(41)
  SysIpcOpUserSetPasswordRequest* = U32(42)
  SysIpcOpUserSetPasswordResponse* = U32(43)

  SysFdMax* = U32(8)
  SysFdPathMax* = U32(128)
  SysPipeMax* = U32(8)
  SysPipeBufSize* = U32(512)
  SysOpenRead* = U32(1)
  SysOpenWrite* = U32(2)
  SysOpenCreate* = U32(4)
  SysOpenTrunc* = U32(8)
  SysOpenAppend* = U32(16)
  SysSeekSet* = U32(0)
  SysSeekCur* = U32(1)
  SysSeekEnd* = U32(2)
  SysFdKindFile* = U32(0)
  SysFdKindStdin* = U32(1)
  SysFdKindStdout* = U32(2)
  SysFdKindStderr* = U32(3)
  SysFdKindConsole* = U32(4)
  SysFdKindPipe* = U32(5)
  SysPollMaxEvents* = U32(16)
  SysPollFdRead* = U32(1)
  SysPollFdWrite* = U32(2)
  SysPollIpcRead* = U32(4)
  SysPollPidExit* = U32(8)
  SysPollTimer* = U32(16)
  SysPollError* = U32(0x80000000'u32)
  SysSignalNone* = U32(0)
  SysSignalTerminate* = U32(1)
  SysSignalInterrupt* = U32(2)
  SysSignalChildExited* = U32(3)
  SysSignalServiceStopped* = U32(4)
  SysSignalMax* = U32(31)

  SysSetUserRootOnly* = I32(-2)

  SysErrOk* = I32(0)
  SysErrPerm* = I32(1)
  SysErrNoEnt* = I32(2)
  SysErrAccess* = I32(13)
  SysErrNotDir* = I32(20)
  SysErrIsDir* = I32(21)
  SysErrInval* = I32(22)
  SysErrCap* = I32(100)

  SysProcessMaxSlots* = U32(32)
  SysProcessUnused* = U32(0)
  SysProcessRunnable* = U32(1)
  SysProcessRunning* = U32(2)
  SysProcessSleeping* = U32(3)
  SysProcessZombie* = U32(4)
  SysProcListAllSlots* = U64(1)
  SysExecNoProcess* = I32(-2)
  SysExecNoEntry* = I32(-3)
  SysExecPermission* = I32(-4)

  SysServiceKindBlock* = U32(0)
  SysServiceKindFs* = U32(1)
  SysServiceKindManager* = U32(2)
  SysServiceKindProcess* = U32(3)
  SysServiceKindNet* = U32(4)
  SysServiceKindProcFs* = U32(5)
  SysServiceKindUser* = U32(6)
  SysServiceNameMax* = U32(16)

type
  SysProcessInfo* {.packed.} = object
    pid*: I32
    ppid*: I32
    uid*: U32
    gid*: U32
    state*: U32
    isUser*: U32
    cpuTicks*: U64
    memoryPages*: U64
    cpuPercent*: U32
    textVa*: U64
    textMemSize*: U64
    rodataVa*: U64
    rodataMemSize*: U64
    dataVa*: U64
    dataMemSize*: U64
    bssVa*: U64
    bssMemSize*: U64
    stackTop*: U64
    stackPages*: U64
    heapStart*: U64
    heapPages*: U64
    requestedCapabilityMask*: U32
    capabilityMask*: U32
    pendingSignals*: U32
    exePath*: array[SysProcessNameMax, char]

  SysDateTime* {.packed.} = object
    year*: U32
    month*: U32
    day*: U32
    hour*: U32
    minute*: U32
    second*: U32
  
  SysTrapCount* {.packed.} = object
    instructionAddressMissaligned*: U64
    instructionAccessFault*: U64
    illegalInstruction*: U64
    breakpoint*: U64
    loadAddressMisaligned*: U64
    loadAccessFault*: U64
    storeAMOAddressMisaligned*: U64
    storeAMOAccessFault*: U64
    environmentCallFromUMode*: U64
    environmentCallFromSMode*: U64
    instructionPageFault*: U64
    loadPageFault*: U64
    storeAMOPageFault*: U64
    supervisorTimer*: U64

  SysBitmapInfo* {.packed.} = object
    total*: U64
    used*: U64
    free*: U64

  SysFsInfoEntry* {.packed.} = object
    name*: array[SysFsInfoNameMax, char]
    fsType*: array[SysFsInfoNameMax, char]
    mount*: array[SysFsInfoNameMax, char]
    blockSize*: U64
    totalBlocks*: U64
    usedBlocks*: U64
    freeBlocks*: U64
    totalFiles*: U64
    usedFiles*: U64
    freeFiles*: U64
    readonly*: U32

  SysCpuInfo* {.packed.} = object
    totalTicks*: U64
    windowTicks*: U64
    idleTicks*: U64
    busyTicks*: U64
    usagePercent*: U32

  SysPollEvent* {.packed.} = object
    target*: I32
    events*: U32
    revents*: U32

  SysNetDeviceInfo* {.packed.} = object
    found*: U32
    initialized*: U32
    mmioBase*: U64
    deviceId*: U32
    vendorId*: U32
    mac*: array[SysNetMacLen, U8]

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
    capabilityMask*: U32
    uid*: U32
    gid*: U32
    data*: array[SysIpcMessageMax, char]

  SysFsRequest* {.packed.} = object
    id*: U64
    op*: U32
    uid*: U32
    gid*: U32
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
  
  SysFdInfo* {.packed.} = object
    fd*: I32
    used*: U32
    kind*: U32
    flags*: U32
    offset*: U64
    size*: U64
    pipeId*: I32
    path*: array[SysFdPathMax, char]
