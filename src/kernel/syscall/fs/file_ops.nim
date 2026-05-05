import ../../../lib/types
import ../../fs/dirent
import ../../fs/fs
import ../../mm/usercopy

const
  SysPathMax = U64(128)
  SysDirEntryMax = U64(32)
  SysFileIoMax = U64(4096)

var
  pathBuf: array[SysPathMax, char]
  dirEntries: array[SysDirEntryMax, FsDirEntry]
  fileBuf: array[SysFileIoMax, U8]


proc readPath(pathVal: U64, defaultRoot: bool = false): cstring =
  if pathVal == 0:
    if defaultRoot:
      return "/"
    return nil

  if copyUserCString(addr pathBuf[0], pathVal, SysPathMax) < 0:
    return nil

  cast[cstring](addr pathBuf[0])


proc syscallLs*(pathVal, entriesVal, maxEntries: U64): U64 =
  if entriesVal == 0 or maxEntries == 0:
    return U64(-1'i64)

  let path = readPath(pathVal, true)
  if path == nil:
    return U64(-1'i64)

  let countMax =
    if maxEntries > SysDirEntryMax:
      SysDirEntryMax
    else:
      maxEntries
  let count = fsReadDirEntries(path, addr dirEntries[0], countMax)
  if count < 0:
    return U64(-1'i64)

  let bytes = U64(count) * U64(sizeof(FsDirEntry))
  if copyToUser(entriesVal, addr dirEntries[0], bytes) != 0:
    return U64(-1'i64)

  U64(count)


proc syscallMkdir*(path: U64): U64 =
  let copiedPath = readPath(path)
  if copiedPath == nil:
    return U64(-1'i64)

  U64(fsMkdir(copiedPath))


proc syscallUnlink*(path: U64): U64 =
  let copiedPath = readPath(path)
  if copiedPath == nil:
    return U64(-1'i64)

  U64(fsUnlink(copiedPath))


proc syscallRmdir*(path: U64): U64 =
  let copiedPath = readPath(path)
  if copiedPath == nil:
    return U64(-1'i64)

  U64(fsRmdir(copiedPath))


proc syscallReadFile*(path, buf, capacity: U64): U64 =
  if buf == 0 or capacity > SysFileIoMax:
    return U64(-1'i64)

  let copiedPath = readPath(path)
  if copiedPath == nil:
    return U64(-1'i64)

  let readLen = fsReadFile(copiedPath, addr fileBuf[0], capacity)
  if readLen < 0:
    return U64(-1'i64)
  if copyToUser(buf, addr fileBuf[0], U64(readLen)) != 0:
    return U64(-1'i64)

  U64(readLen)


proc syscallWriteFile*(path, buf, size: U64): U64 =
  if size > SysFileIoMax:
    return U64(-1'i64)

  let copiedPath = readPath(path)
  if copiedPath == nil:
    return U64(-1'i64)
  if copyFromUser(addr fileBuf[0], buf, size) != 0:
    return U64(-1'i64)

  U64(fsWriteFile(copiedPath, addr fileBuf[0], size))
