import ./types


const
  SysCapNone* = U32(0)
  SysCapServiceManager* = U32(1'u32 shl 0)
  SysCapRawFs* = U32(1'u32 shl 1)
  SysCapRawBlock* = U32(1'u32 shl 2)
  SysCapRawNet* = U32(1'u32 shl 3)
  SysCapProcessList* = U32(1'u32 shl 4)
  SysCapProcessKill* = U32(1'u32 shl 5)
  SysCapAllKnown* = SysCapServiceManager or SysCapRawFs or SysCapRawBlock or
    SysCapRawNet or SysCapProcessList or SysCapProcessKill
