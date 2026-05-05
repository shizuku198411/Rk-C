import ../../../lib/types
import ../../syscall/fs/fs_service_ops
import ../../mm/usercopy

const
  SysPathMax = U64(128)
  SysDirEntryMax = U64(32)
  SysFileIoMax = U64(4096)

var
  pathBuf: array[SysPathMax, char]
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
  serviceLs(path, entriesVal, countMax)


proc syscallMkdir*(path: U64): U64 =
  let copiedPath = readPath(path)
  if copiedPath == nil:
    return U64(-1'i64)

  serviceMkdir(copiedPath)


proc syscallUnlink*(path: U64): U64 =
  let copiedPath = readPath(path)
  if copiedPath == nil:
    return U64(-1'i64)

  serviceUnlink(copiedPath)


proc syscallRmdir*(path: U64): U64 =
  let copiedPath = readPath(path)
  if copiedPath == nil:
    return U64(-1'i64)

  serviceRmdir(copiedPath)


proc syscallReadFile*(path, buf, capacity: U64): U64 =
  if buf == 0 or capacity > SysFileIoMax:
    return U64(-1'i64)

  let copiedPath = readPath(path)
  if copiedPath == nil:
    return U64(-1'i64)

  serviceReadFile(copiedPath, buf, capacity)


proc syscallWriteFile*(path, buf, size: U64): U64 =
  if size > SysFileIoMax:
    return U64(-1'i64)

  let copiedPath = readPath(path)
  if copiedPath == nil:
    return U64(-1'i64)
  if copyFromUser(addr fileBuf[0], buf, size) != 0:
    return U64(-1'i64)

  serviceWriteFile(copiedPath, addr fileBuf[0], size)
