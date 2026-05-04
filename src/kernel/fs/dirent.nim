import ../../lib/types

const
  FsDirEntryNameMax* = 16
  FsDirEntryTypeFile* = U32(1)
  FsDirEntryTypeDir* = U32(2)
  FsDirEntryTypeMount* = U32(3)

type
  FsDirEntry* {.packed.} = object
    typ*: U32
    size*: U32
    name*: array[FsDirEntryNameMax, char]
