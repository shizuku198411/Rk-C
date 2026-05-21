import ./history
import ../../lib/core/io
import ../../lib/core/pathutils
import ../../lib/core/passwd
import ../../lib/core/strutils
import ../../lib/core/syscall
import ../../lib/core/userdb


proc changeDirectory*(path: cstring) =
  if isEmpty(path):
    write("usage: cd <path>\n")
    return

  let resolved = resolvePath(path)
  if resolved == nil:
    write("cd: path too long\n")
    return

  if sysSetCwd(resolved) != 0:
    write("cd: failed\n")


proc switchUser*(name: cstring) =
  if isEmpty(name):
    write("usage: su <user>\n")
    return

  var entry: PasswdEntry
  var passwordBuf: array[LoginLineMax, char]
  write("password: ")
  let password = readLoginLine(passwordBuf, false)
  if not authenticateUser(name, password, entry):
    write("su: incorrect username or password\n")
    return

  saveHistory()

  let rc = sysSetUser(entry.uid, entry.gid)
  if rc != 0:
    write("su: failed\n")
  else:
    discard sysSetCwd(cast[cstring](addr entry.home[0]))
    clearHistory()
    loadHistory()


proc printTrapCount*() =
  var trapCount: SysTrapCount
  if sysTraps(addr trapCount) != 0:
    write("traps: failed\n")
    return

  write("trap count:\n")
  write("  instruction address misaligned : ")
  writeUnsigned(trapCount.instructionAddressMissaligned)
  write("\n")
  write("  instruction access fault       : ")
  writeUnsigned(trapCount.instructionAccessFault)
  write("\n")
  write("  illegal instruction            : ")
  writeUnsigned(trapCount.illegalInstruction)
  write("\n")
  write("  breakpoint                     : ")
  writeUnsigned(trapCount.breakpoint)
  write("\n")
  write("  load address misaligned        : ")
  writeUnsigned(trapCount.loadAddressMisaligned)
  write("\n")
  write("  load access fault              : ")
  writeUnsigned(trapCount.loadAccessFault)
  write("\n")
  write("  store/amo address misaligned   : ")
  writeUnsigned(trapCount.storeAMOAddressMisaligned)
  write("\n")
  write("  store/amo access fault         : ")
  writeUnsigned(trapCount.storeAMOAccessFault)
  write("\n")
  write("  environment call from u-mode   : ")
  writeUnsigned(trapCount.environmentCallFromUMode)
  write("\n")
  write("  environment call from s-mode   : ")
  writeUnsigned(trapCount.environmentCallFromSMode)
  write("\n")
  write("  instruction page fault         : ")
  writeUnsigned(trapCount.instructionPageFault)
  write("\n")
  write("  load page fault                : ")
  writeUnsigned(trapCount.loadPageFault)
  write("\n")
  write("  store/amo page fault           : ")
  writeUnsigned(trapCount.storeAMOPageFault)
  write("\n")
  write("  supervisor timer               : ")
  writeUnsigned(trapCount.supervisorTimer)
  write("\n")


proc printBitmapInfo*() =
  var info: SysBitmapInfo
  if sysGetBitMap(addr info) != 0:
    write("bitmap: failed\n")
    return

  write("bitmap:\n")
  write("  total: ")
  writeUnsigned(info.total)
  write(" pages\n")
  write("  used : ")
  writeUnsigned(info.used)
  write(" pages\n")
  write("  free : ")
  writeUnsigned(info.free)
  write(" pages\n")
