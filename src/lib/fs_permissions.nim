import types
import user_ids

const
  FsModeNone* = U32(0)

  FsPermOwnerRead* = U32(256)  # 0400
  FsPermOwnerWrite* = U32(128) # 0200
  FsPermOwnerExec* = U32(64)   # 0100
  FsPermGroupRead* = U32(32)   # 0040
  FsPermGroupWrite* = U32(16)  # 0020
  FsPermGroupExec* = U32(8)    # 0010
  FsPermOtherRead* = U32(4)    # 0004
  FsPermOtherWrite* = U32(2)   # 0002
  FsPermOtherExec* = U32(1)    # 0001

  FsModeDirDefault* = U32(493)      # 0755
  FsModeFileDefault* = U32(420)     # 0644
  FsModePublicDir* = U32(511)       # 0777
  FsModeReadonlyDir* = U32(365)     # 0555
  FsModeReadonlyFile* = U32(365)    # 0555
  FsModeDeviceFile* = U32(438)      # 0666


proc fsModeAllows*(nodeUid, nodeGid, mode, uid, gid: U32,
                   ownerBit, groupBit, otherBit: U32): bool =
  if uid == RootUid:
    return true

  if uid == nodeUid:
    return (mode and ownerBit) != U32(0)

  if gid == nodeGid:
    return (mode and groupBit) != U32(0)

  (mode and otherBit) != U32(0)


proc fsModeAllowsRead*(nodeUid, nodeGid, mode, uid, gid: U32): bool =
  fsModeAllows(
    nodeUid,
    nodeGid,
    mode,
    uid,
    gid,
    FsPermOwnerRead,
    FsPermGroupRead,
    FsPermOtherRead,
  )


proc fsModeAllowsWrite*(nodeUid, nodeGid, mode, uid, gid: U32): bool =
  fsModeAllows(
    nodeUid,
    nodeGid,
    mode,
    uid,
    gid,
    FsPermOwnerWrite,
    FsPermGroupWrite,
    FsPermOtherWrite,
  )


proc fsModeAllowsExecute*(nodeUid, nodeGid, mode, uid, gid: U32): bool =
  fsModeAllows(
    nodeUid,
    nodeGid,
    mode,
    uid,
    gid,
    FsPermOwnerExec,
    FsPermGroupExec,
    FsPermOtherExec,
  )
