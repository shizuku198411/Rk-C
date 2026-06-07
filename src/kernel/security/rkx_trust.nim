## Parses and stores the build-time RKX trusted manifest.
import ../../lib/crypto/sha256
import ../../lib/fixed_string
import ../../lib/syscall_types
import ../../lib/types
import ../fs/fs


const
  RkxTrustManifestEntryName = cstring"__rkxtrust"
  RkxTrustManifestMagic = cstring"RKXTRUST1"
  RkxTrustManifestMaxBytes = U64(8192)
  RkxTrustMaxEntries* = 64
  RkxTrustPathMax* = 64
  RkxTrustHashBytes* = 32
  RkxTrustHashChunkBytes = U64(512)


type
  RkxTrustHash* = array[RkxTrustHashBytes, U8]

  RkxTrustEntry* = object
    used*: bool
    verified*: bool
    path*: array[RkxTrustPathMax, char]
    hash*: RkxTrustHash


var
  manifestBuf: array[RkxTrustManifestMaxBytes.int + 1, char]
  trustEntries: array[RkxTrustMaxEntries, RkxTrustEntry]
  trustEntryCount: U32
  trustVerifiedCount: U32
  trustManifestLoaded: bool
  trustManifestValid: bool
  hashBuf: array[RkxTrustHashChunkBytes.int, U8]


## Resets the in-kernel RKX trust manifest state.
proc resetRkxTrustState() =
  trustEntryCount = U32(0)
  trustVerifiedCount = U32(0)
  trustManifestLoaded = false
  trustManifestValid = false

  var i = 0
  while i < RkxTrustMaxEntries:
    trustEntries[i] = RkxTrustEntry()
    inc i


## Returns true when the byte is horizontal space.
proc isSpace(ch: char): bool =
  ch == ' ' or ch == '\t'


## Returns true when the byte is a line break.
proc isLineBreak(ch: char): bool =
  ch == '\n' or ch == '\r'


## Skips horizontal space within one manifest line.
proc skipSpaces(buf: ptr UncheckedArray[char], pos: var U64) =
  while isSpace(buf[pos]):
    inc pos


## Skips the rest of the current manifest line.
proc skipLine(buf: ptr UncheckedArray[char], pos: var U64) =
  while buf[pos] != '\0' and not isLineBreak(buf[pos]):
    inc pos
  while isLineBreak(buf[pos]):
    inc pos


## Reads one token from the manifest buffer into a fixed output buffer.
proc readToken(buf: ptr UncheckedArray[char], pos: var U64,
               dst: ptr UncheckedArray[char], capacity: U64): bool =
  if dst == nil or capacity == U64(0):
    return false

  skipSpaces(buf, pos)
  if buf[pos] == '\0' or isLineBreak(buf[pos]):
    return false

  var len = U64(0)
  while buf[pos] != '\0' and not isSpace(buf[pos]) and not isLineBreak(buf[pos]):
    if len + U64(1) >= capacity:
      return false
    dst[len] = buf[pos]
    inc len
    inc pos

  dst[len] = '\0'
  true


## Returns the lowercase hexadecimal value for one character.
proc hexValue(ch: char): int =
  if ch >= '0' and ch <= '9':
    return int(ord(ch) - ord('0'))
  if ch >= 'a' and ch <= 'f':
    return int(ord(ch) - ord('a') + 10)

  -1


## Parses a lowercase 64-character SHA-256 hex string.
proc parseSha256Hex(src: ptr UncheckedArray[char], outHash: var RkxTrustHash): bool =
  var i = 0
  while i < RkxTrustHashBytes:
    let hi = hexValue(src[i * 2])
    let lo = hexValue(src[i * 2 + 1])
    if hi < 0 or lo < 0:
      return false

    outHash[i] = U8((hi shl 4) or lo)
    inc i

  src[RkxTrustHashBytes * 2] == '\0'


## Copies a parsed manifest path into a trust entry.
proc copyTrustPath(dst: var array[RkxTrustPathMax, char],
                   src: ptr UncheckedArray[char]): bool =
  var i = 0
  while i < RkxTrustPathMax:
    dst[i] = '\0'
    inc i

  i = 0
  while src[i] != '\0':
    if i + 1 >= RkxTrustPathMax:
      return false
    dst[i] = src[i]
    inc i

  true


## Returns true when a manifest path is already present.
proc hasDuplicatePath(path: cstring): bool =
  var i = U32(0)
  while i < trustEntryCount:
    if fixedCStringEq(trustEntries[i].path, path):
      return true
    inc i

  false


## Adds one parsed manifest entry to the fixed trust table.
proc addTrustEntry(path: ptr UncheckedArray[char], hash: RkxTrustHash): bool =
  if trustEntryCount >= U32(RkxTrustMaxEntries):
    return false
  if path[0] != '/':
    return false
  if hasDuplicatePath(cast[cstring](path)):
    return false

  let idx = int(trustEntryCount)
  trustEntries[idx].used = true
  trustEntries[idx].verified = false
  if not copyTrustPath(trustEntries[idx].path, path):
    trustEntries[idx] = RkxTrustEntry()
    return false

  trustEntries[idx].hash = hash
  inc trustEntryCount
  true


## Returns true when two SHA-256 digests are equal.
proc hashEquals(left, right: RkxTrustHash): bool =
  var diff = U8(0)
  var i = 0
  while i < RkxTrustHashBytes:
    diff = diff or (left[i] xor right[i])
    inc i

  diff == U8(0)


## Computes the SHA-256 digest of one filesystem path.
proc hashFile(path: cstring, outHash: var RkxTrustHash): bool =
  let fileSize = fsAppfsFileSize(path)
  if fileSize < 0:
    return false

  var ctx = Sha256Ctx()
  sha256Init(ctx)

  var offset = U64(0)
  let total = U64(fileSize)
  while offset < total:
    var chunk = total - offset
    if chunk > RkxTrustHashChunkBytes:
      chunk = RkxTrustHashChunkBytes

    let readLen = fsReadFileRange(path, addr hashBuf[0], offset, chunk)
    if readLen < 0 or U64(readLen) != chunk:
      return false

    sha256Update(ctx, addr hashBuf[0], U32(readLen))
    offset += chunk

  sha256Final(ctx, addr outHash[0])
  true


## Verifies all parsed manifest entries against current appfs contents.
proc verifyTrustEntries() =
  trustVerifiedCount = U32(0)

  var i = U32(0)
  while i < trustEntryCount:
    trustEntries[i].verified = false

    var actual: RkxTrustHash
    if hashFile(cast[cstring](addr trustEntries[i].path[0]), actual) and
        hashEquals(actual, trustEntries[i].hash):
      trustEntries[i].verified = true
      inc trustVerifiedCount

    inc i


## Parses a non-empty non-comment manifest entry line.
proc parseEntryLine(buf: ptr UncheckedArray[char], pos: var U64): bool =
  var path: array[RkxTrustPathMax, char]
  var algorithm: array[8, char]
  var hashText: array[RkxTrustHashBytes * 2 + 1, char]
  var hash: RkxTrustHash

  if not readToken(buf, pos, cast[ptr UncheckedArray[char]](addr path[0]), U64(RkxTrustPathMax)):
    return false
  if not readToken(buf, pos, cast[ptr UncheckedArray[char]](addr algorithm[0]), U64(algorithm.len)):
    return false
  if not readToken(buf, pos, cast[ptr UncheckedArray[char]](addr hashText[0]), U64(hashText.len)):
    return false

  skipSpaces(buf, pos)
  if buf[pos] != '\0' and not isLineBreak(buf[pos]):
    return false
  if not fixedCStringEq(algorithm, cstring"sha256"):
    return false
  if not parseSha256Hex(cast[ptr UncheckedArray[char]](addr hashText[0]), hash):
    return false
  if not addTrustEntry(cast[ptr UncheckedArray[char]](addr path[0]), hash):
    return false

  skipLine(buf, pos)
  true


## Parses the complete trusted manifest buffer.
proc parseManifest(buf: ptr UncheckedArray[char]): bool =
  var pos = U64(0)
  var magic: array[16, char]

  if not readToken(buf, pos, cast[ptr UncheckedArray[char]](addr magic[0]), U64(magic.len)):
    return false
  if not fixedCStringEq(magic, RkxTrustManifestMagic):
    return false

  skipSpaces(buf, pos)
  if buf[pos] != '\0' and not isLineBreak(buf[pos]):
    return false
  skipLine(buf, pos)

  while buf[pos] != '\0':
    skipSpaces(buf, pos)
    if buf[pos] == '#':
      skipLine(buf, pos)
    elif isLineBreak(buf[pos]):
      skipLine(buf, pos)
    elif not parseEntryLine(buf, pos):
      return false

  true


## Loads and parses the RKX trusted manifest from appfs internal metadata.
proc rkxTrustInit*(): bool =
  resetRkxTrustState()

  let readLen = fsReadAppfsInternal(
    RkxTrustManifestEntryName,
    addr manifestBuf[0],
    RkxTrustManifestMaxBytes,
  )
  if readLen < 0:
    return false

  manifestBuf[readLen] = '\0'
  trustManifestLoaded = true
  trustManifestValid = parseManifest(cast[ptr UncheckedArray[char]](addr manifestBuf[0]))
  if trustManifestValid:
    verifyTrustEntries()

  trustManifestValid


## Returns whether a trusted manifest was loaded and parsed successfully.
proc rkxTrustReady*(): bool =
  trustManifestLoaded and trustManifestValid


## Returns the number of parsed RKX trust entries.
proc rkxTrustEntryCount*(): U32 =
  if not rkxTrustReady():
    return U32(0)

  trustEntryCount


## Returns the number of manifest entries verified against appfs contents.
proc rkxTrustVerifiedEntryCount*(): U32 =
  if not rkxTrustReady():
    return U32(0)

  trustVerifiedCount


## Copies one trust table entry into a syscall-facing structure.
proc rkxTrustCopyEntry*(index: U32, outEntry: var SysRkxTrustInfo): bool =
  if not rkxTrustReady() or index >= trustEntryCount:
    return false

  let src = addr trustEntries[index]
  outEntry = SysRkxTrustInfo()
  outEntry.used =
    if src.used:
      U32(1)
    else:
      U32(0)
  outEntry.verified =
    if src.verified:
      U32(1)
    else:
      U32(0)

  var i = U32(0)
  while i < SysRkxTrustPathMax and i < U32(RkxTrustPathMax):
    outEntry.path[i] = src.path[i]
    inc i

  i = U32(0)
  while i < SysRkxTrustHashBytes and i < U32(RkxTrustHashBytes):
    outEntry.hash[i] = src.hash[i]
    inc i

  true


## Returns whether a path is present in the manifest and verified against appfs.
proc rkxPathIntegrityVerified*(path: cstring): bool =
  if path == nil or not rkxTrustReady():
    return false

  var i = U32(0)
  while i < trustEntryCount:
    if trustEntries[i].used and trustEntries[i].verified and
        fixedCStringEq(trustEntries[i].path, path):
      return true
    inc i

  false


## Looks up a parsed trusted manifest entry by executable path.
proc rkxTrustLookup*(path: cstring, outHash: ptr RkxTrustHash): bool =
  if path == nil or outHash == nil or not rkxTrustReady():
    return false

  var i = U32(0)
  while i < trustEntryCount:
    if trustEntries[i].used and fixedCStringEq(trustEntries[i].path, path):
      outHash[] = trustEntries[i].hash
      return true
    inc i

  false
