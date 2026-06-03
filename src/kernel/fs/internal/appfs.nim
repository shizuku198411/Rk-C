## Loads and resolves executable files stored in the appfs image.

## Implements the appfs read bytes kernel helper.
proc appfsReadBytes(absOff: U64, outBuf: pointer, n: U64): int =
  if outBuf == nil and n > 0:
    return -1

  let dst = cast[ptr UncheckedArray[U8]](outBuf)
  var done = U64(0)
  while done < n:
    let cur = absOff + done
    let blk = cur div BlockSize
    let inBlk = cur mod BlockSize
    when defined(platformMilkVDuo256m):
      ##
      ## appfs backs executable images used to start user services.  Keep this
      ## path independent from blockd so service startup cannot depend on the
      ## block service that is still being assembled.
      ##
      if blockRead(blk, addr blockBuf[0]) < 0:
        return -1
    else:
      if serviceBlockRead(blk, addr blockBuf[0]) < 0:
        return -1

    var chunk = BlockSize - inBlk
    if chunk > n - done:
      chunk = n - done

    var i = U64(0)
    while i < chunk:
      dst[done + i] = blockBuf[inBlk + i]
      inc i
    done += chunk
  0


## Implements the appfs name eq kernel helper.
proc appfsNameEq(entry: ptr AppfsEntry, name: cstring): bool =
  if entry == nil:
    return false

  fixedCStringEq(cast[ptr UncheckedArray[char]](addr entry.name[0]), FsNameMax, name)


## Resolves appfs path.
proc resolveAppfsPath(path: cstring): int =
  if path == nil or not appfsReady:
    return -1
  if not (path[0] == '/' and path[1] == 'b' and path[2] == 'i' and
      path[3] == 'n' and path[4] == '/'):
    return -1

  let name = cast[cstring](unsafeAddr path[5])
  if name[0] == '\0':
    return -1

  var p = 0
  while name[p] != '\0':
    if name[p] == '/':
      return -1
    inc p

  var i = 0
  while i < int(appfsEntryCount):
    if appfsNameEq(addr appfsEntries[i], name):
      return i
    inc i
  -1


## Implements the appfs load kernel helper.
proc appfsLoad(): int =
  var hdr: AppfsHeader
  let base = appfsStartBlock * BlockSize
  if appfsReadBytes(base, addr hdr, U64(sizeof(AppfsHeader))) < 0:
    return -1
  if hdr.magic != AppfsMagic or hdr.count > U32(AppfsMaxEntries):
    return -1

  appfsEntryCount = hdr.count
  if appfsEntryCount > 0:
    let tableBytes = U64(appfsEntryCount) * U64(sizeof(AppfsEntry))
    if appfsReadBytes(base + U64(sizeof(AppfsHeader)), addr appfsEntries[0], tableBytes) < 0:
      return -1

  appfsReady = true
  0
