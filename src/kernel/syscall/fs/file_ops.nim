import ../../../lib/types
import ../../fs/dirent
import ../../fs/fs

proc syscallLs*(pathVal, entriesVal, maxEntries: U64): U64 =
  let path =
    if pathVal == 0: cstring("/")
    else: cast[cstring](pathVal)
  U64(fsReadDirEntries(path, cast[ptr FsDirEntry](entriesVal), maxEntries))

proc syscallMkdir*(path: U64): U64 =
  U64(fsMkdir(cast[cstring](path)))

proc syscallUnlink*(path: U64): U64 =
  U64(fsUnlink(cast[cstring](path)))

proc syscallRmdir*(path: U64): U64 =
  U64(fsRmdir(cast[cstring](path)))

proc syscallReadFile*(path, buf, capacity: U64): U64 =
  U64(fsReadFile(cast[cstring](path), cast[pointer](buf), capacity))

proc syscallWriteFile*(path, buf, size: U64): U64 =
  U64(fsWriteFile(cast[cstring](path), cast[pointer](buf), size))
