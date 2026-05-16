import ./types

const
  RkxMagic* = U32(0x31584b52)   # "RKX1"
  RkxVersion* = U32(1)


type
  RkxHeader* {.packed.} = object
    magic*: U32
    version*: U32
    headerSize*: U32
    reserved*: U32

    entryVa*: U64

    textVa*: U64
    textOff*: U64
    textFileSize*: U64
    textMemSize*: U64

    rodataVa*: U64
    rodataOff*: U64
    rodataFileSize*: U64
    rodataMemSize*: U64

    dataVa*: U64
    dataOff*: U64
    dataFileSize*: U64
    dataMemSize*: U64

    bssVa*: U64
    bssMemSize*: U64
