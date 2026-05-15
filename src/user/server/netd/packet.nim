import ../../lib/core/io
import ../../lib/core/syscall
import ../../lib/net/ipaddr


proc printHexNibble*(value: U64) =
  let digit = value and 0xf'u64
  if digit < 10:
    writeChar(char(ord('0') + int(digit)))
  else:
    writeChar(char(ord('a') + int(digit - 10)))


proc writeHex*(value: U64) =
  write("0x")
  var shift = 60
  var started = false

  while shift >= 0:
    let digit = (value shr U64(shift)) and 0xf'u64
    if digit != 0 or started or shift == 0:
      started = true
      printHexNibble(digit)
    shift -= 4


proc writeHexByte*(value: U8) =
  printHexNibble(U64(value shr 4))
  printHexNibble(U64(value and 0x0f'u8))


proc writeMacValue*(value: ptr array[SysNetMacLen, U8]) =
  var i = 0
  while i < SysNetMacLen:
    if i > 0:
      writeChar(':')
    writeHexByte(value[][i])
    inc i


proc writeIp*(value: U32) =
  writeIpv4Addr(value)


proc put16*(buf: var array[SysNetPacketMax, U8], off: int, value: U16) =
  buf[off] = U8((value shr 8) and 0xff'u16)
  buf[off + 1] = U8(value and 0xff'u16)


proc put32*(buf: var array[SysNetPacketMax, U8], off: int, value: U32) =
  buf[off] = U8((value shr 24) and 0xff'u32)
  buf[off + 1] = U8((value shr 16) and 0xff'u32)
  buf[off + 2] = U8((value shr 8) and 0xff'u32)
  buf[off + 3] = U8(value and 0xff'u32)


proc get16*(buf: ptr array[SysNetPacketMax, U8], off: int): U16 =
  (U16(buf[][off]) shl 8) or U16(buf[][off + 1])


proc get32*(buf: ptr array[SysNetPacketMax, U8], off: int): U32 =
  (U32(buf[][off]) shl 24) or (U32(buf[][off + 1]) shl 16) or
    (U32(buf[][off + 2]) shl 8) or U32(buf[][off + 3])


proc clearTx*(txBuf: var array[SysNetPacketMax, U8]) =
  var i = 0
  while i < SysNetPacketMax:
    txBuf[i] = 0
    inc i


proc copyMacToFrame*(txBuf: var array[SysNetPacketMax, U8], off: int,
                     value: ptr array[SysNetMacLen, U8]) =
  var i = 0
  while i < SysNetMacLen:
    txBuf[off + i] = value[][i]
    inc i


proc copyBroadcastToFrame*(txBuf: var array[SysNetPacketMax, U8], off: int) =
  var i = 0
  while i < SysNetMacLen:
    txBuf[off + i] = 0xff'u8
    inc i


proc copyMacFromRx*(rxBuf: ptr array[SysNetPacketMax, U8],
                    dst: var array[SysNetMacLen, U8], srcOff: int) =
  var i = 0
  while i < SysNetMacLen:
    dst[i] = rxBuf[][srcOff + i]
    inc i


proc checksum*(buf: ptr array[SysNetPacketMax, U8], off: int, len: int): U16 =
  var sum = U32(0)
  var i = 0
  while i + 1 < len:
    sum += U32(get16(buf, off + i))
    i += 2

  if i < len:
    sum += U32(buf[][off + i]) shl 8

  while (sum shr 16) != 0:
    sum = (sum and 0xffff'u32) + (sum shr 16)

  U16(not sum and 0xffff'u32)


proc sendFrame*(txBuf: var array[SysNetPacketMax, U8], size: U64): bool =
  let paddedSize =
    if size < 60:
      U64(60)
    else:
      size

  sysRawNetSend(addr txBuf[0], paddedSize) == I32(paddedSize)
