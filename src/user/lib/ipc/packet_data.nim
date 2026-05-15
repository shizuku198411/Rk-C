import ../core/syscall


proc setBoolResultPacket*(packet: ptr SysIpcPacket, op: U32, ok: bool) =
  packet[] = SysIpcPacket()
  packet.op = op
  packet.arg0 =
    if ok:
      U64(0)
    else:
      U64(-1'i64)


proc setI32ResultPacket*(packet: ptr SysIpcPacket, op: U32, result: I32) =
  packet[] = SysIpcPacket()
  packet.op = op
  packet.arg0 =
    if result >= 0:
      U64(result)
    else:
      U64(-1'i64)


proc copyToPacketData*(packet: ptr SysIpcPacket, src: pointer, len: U32): U32 =
  if packet == nil or src == nil:
    return U32(0)

  let data = cast[ptr UncheckedArray[char]](src)
  var i = U32(0)
  while i < len and i < U32(SysIpcMessageMax):
    packet.data[int(i)] = data[int(i)]
    inc i

  packet.len = i
  i


proc copyFromPacketData*(dst: pointer, packet: ptr SysIpcPacket, capacity: U32): U32 =
  if dst == nil or packet == nil:
    return U32(0)

  let data = cast[ptr UncheckedArray[char]](dst)
  var i = U32(0)
  while i < packet.len and i < capacity and i < U32(SysIpcMessageMax):
    data[int(i)] = packet.data[int(i)]
    inc i

  i
