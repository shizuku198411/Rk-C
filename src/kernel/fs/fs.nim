## Implements the root filesystem, appfs, devfs views, VFS dispatch, and permissions.
import ../../lib/fixed_string
import ../../lib/fs_permissions
import ../../lib/mem
import ../../lib/syscall_types
import ../../lib/types
import ../../lib/user_ids
import ../../generated/version
import ../dev/console
import ../fs/dirent
import ../fs/tmpfs
import ../lib/path
import ../syscall/blk/block_service_ops

when defined(platformMilkVDuo256m):
  import ../fs/blockdev except BlockSize, BlockCount
  import ../fs/partition
  import ../../platform/milkv_duo256m/memory_layout

const
  FsMagic = U32(0x4e465333) # NFS3
  FsMaxNodes* = 128
  FsNameMax* = 16
  AppfsMagic = U32(0x41504653) # APFS
  AppfsDefaultStartBlock = U64(4096)
  AppfsMaxEntries = 64
  FsMetaBlocks = U64(16)
  FsMetaBytes = 8192
  FsDataStartBlock = FsMetaBlocks
  FsDataBlockCount = int(AppfsDefaultStartBlock - FsDataStartBlock)
  FsDataBitmapBytes = (FsDataBlockCount + 7) div 8

  FsTypeFile = U32(1)
  FsTypeDir = U32(2)
  FsTypeMount = U32(3)
  VfsMaxMounts = 4
  DevEntryCount = 4
  OsReleaseContent = cstring(
    "NAME=\"Rk-C\"\n" &
    "VERSION=\"" & RkcVersion & "\"\n" &
    "VERSION_ID=\"" & RkcVersionId & "\"\n" &
    "ID=rk-c\n" &
    "ID_LIKE=rk-c\n" &
    "HOME_URL=\"https://shizuku198411.github.io/Rk-C-Doc\"\n" &
    "GITHUB_URL=\"https://github.com/shizuku198411/Rk-C\"\n"
  )

type
  AppfsEntry {.packed.} = object
    name: array[FsNameMax, char]
    dataOff: U32
    size: U32

  AppfsHeader {.packed.} = object
    magic: U32
    count: U32

  VfsBackend = enum
    vfsRootfs,
    vfsTmpfs

  VfsMount = object
    used: bool
    path: array[FsNameMax, char]
    pathLen: int
    backend: VfsBackend

  FsNode {.packed.} = object
    used: U32
    typ: U32
    parent: U32
    size: U32
    startBlock: U32
    blockCount: U32
    name: array[FsNameMax, char]
    uid: U32
    gid: U32
    mode: U32

  FsSuper {.packed.} = object
    magic: U32
    count: U32
    nodes: array[FsMaxNodes, FsNode]
    dataBitmap: array[FsDataBitmapBytes, U8]

var
  superBlock: FsSuper
  superRawBuf: array[FsMetaBytes, U8]
  blockBuf: array[512, U8]
  fsReady: bool
  fsMetaDirty: bool
  fsMetaDeferredWrites: U64
  mounts: array[VfsMaxMounts, VfsMount]
  mountCount: int
  appfsEntries: array[AppfsMaxEntries, AppfsEntry]
  appfsEntryCount: U32
  appfsStartBlock: U64 = AppfsDefaultStartBlock
  appfsReady: bool


let devEntryNames = [
  cstring("stdin"),
  cstring("stdout"),
  cstring("stderr"),
  cstring("console"),
]


## Implements the fs write file kernel helper.
proc fsWriteFile*(path: cstring, data: pointer, size: U64): int
## Implements the fs write file with flags kernel helper.
proc fsWriteFileWithFlags*(path: cstring, data: pointer, size: U64, flags: U32): int
## Implements range writes used by descriptor-based streaming I/O.
proc fsWriteFileRange*(path: cstring, data: pointer, offset, size: U64): int
## Implements the fs rename kernel helper.
proc fsRename*(oldPath, newPath: cstring): int
## Implements the fs chmod kernel helper.
proc fsChmod*(path: cstring, mode: U32): int
## Implements the fs chown kernel helper.
proc fsChown*(path: cstring, uid, gid: U32): int
## Sets the logical block where appfs starts.
proc fsSetAppfsBaseBlock*(baseBlock: U64)
## Returns the logical block where appfs starts.
proc fsAppfsBaseBlock*(): U64
## Ensures a child node exists below an existing directory.
proc ensureDir(parentIdx: int, name: cstring, typ: U32): bool


## Includes defines node metadata defaults and permission-bit checks for rootfs nodes.
include ./internal/metadata


## Includes resolves vfs mount paths and built-in device namespace paths.
include ./internal/mounts_devices


## Includes loads and resolves executable files stored in the appfs image.
include ./internal/appfs


## Includes implements on-disk rootfs allocation, lookup, and byte transfer primitives.
include ./internal/rootfs_store


## Includes initializes the filesystem tree and reports filesystem metadata.
include ./internal/bootstrap_info


## Includes evaluates filesystem access, traversal, and metadata-change permissions.
include ./internal/access_checks


## Includes enumerates directories and answers filesystem node queries.
include ./internal/directory_queries


## Includes performs rootfs mutations and file-content reads and writes.
include ./internal/file_mutations


## Sets the logical block where appfs starts.
proc fsSetAppfsBaseBlock*(baseBlock: U64) =
  appfsStartBlock = baseBlock
  appfsReady = false
  appfsEntryCount = U32(0)


## Returns the logical block where appfs starts.
proc fsAppfsBaseBlock*(): U64 =
  appfsStartBlock


## Loads only appfs metadata without requiring rootfs initialization.
proc fsLoadAppfsOnly*(): int =
  appfsLoad()


## Returns the loaded appfs entry count.
proc fsAppfsEntryCount*(): U32 =
  if not appfsReady:
    return U32(0)

  appfsEntryCount


## Looks up a /bin appfs entry size without requiring fsReady.
proc fsAppfsFileSize*(path: cstring): int =
  let idx = resolveAppfsPath(path)
  if idx < 0:
    return -1

  int(appfsEntries[idx].size)
