type
  U32* = uint32
  U64* = uint64
  I32* = int32

const
  DirEntryNameMax* = 16
  DirEntryTypeFile* = U32(1)
  DirEntryTypeDir* = U32(2)
  DirEntryTypeMount* = U32(3)

type
  DirEntry* {.packed.} = object
    typ*: U32
    size*: U32
    name*: array[DirEntryNameMax, char]

proc sysWrite*(buf: pointer, len: U64): U64 {.importc: "user_sys_write", cdecl.}
proc sysRead*(buf: pointer, len: U64): U64 {.importc: "user_sys_read", cdecl.}
proc sysPs*(): U64 {.importc: "user_sys_ps", cdecl.}
proc sysTicks*(): U64 {.importc: "user_sys_ticks", cdecl.}
proc sysExit*(status: U64) {.importc: "user_sys_exit", cdecl, noreturn.}
proc sysLs*(path: cstring, entries: ptr DirEntry, maxEntries: U64): I32 {.importc: "user_sys_ls", cdecl.}
proc sysCat*(path: cstring): I32 {.importc: "user_sys_cat", cdecl.}
proc sysMkdir*(path: cstring): I32 {.importc: "user_sys_mkdir", cdecl.}
proc sysExec*(path: cstring, arg: cstring): I32 {.importc: "user_sys_exec", cdecl.}
proc sysWait*(pid: I32): U64 {.importc: "user_sys_wait", cdecl.}
proc sysUnlink*(path: cstring): I32 {.importc: "user_sys_unlink", cdecl.}
proc sysRmdir*(path: cstring): I32 {.importc: "user_sys_rmdir", cdecl.}
proc sysShutdown*() {.importc: "user_sys_shutdown", cdecl.}
proc sysGetDateTime*() {.importc: "user_sys_getdatetime", cdecl.}


proc cstrlen*(s: cstring): U64 =
  if s == nil:
    return 0
  var n = U64(0)
  while s[n] != '\0':
    inc n
  n


proc write*(s: cstring) =
  discard sysWrite(cast[pointer](s), cstrlen(s))


proc writeChar*(ch: char) =
  var c = ch
  discard sysWrite(addr c, 1)


proc readChar*(): char =
  var c: char
  discard sysRead(addr c, 1)
  c


proc writeUnsigned*(value: U64) =
  var buf: array[32, char]
  var n = value
  var pos = 32
  if n == 0:
    writeChar('0')
    return

  while n > 0:
    let digit = n mod 10
    dec pos
    buf[pos] = char(ord('0') + int(digit))
    n = n div 10

  discard sysWrite(addr buf[pos], U64(32 - pos))


proc streq*(a, b: cstring): bool =
  if a == nil or b == nil:
    return false
  var i = U64(0)
  while a[i] == b[i]:
    if a[i] == '\0':
      return true
    inc i
  false


proc startsWith2*(s: cstring, a, b: char): bool =
  s != nil and s[0] == a and s[1] == b


proc isEmpty*(s: cstring): bool =
  s == nil or s[0] == '\0'
