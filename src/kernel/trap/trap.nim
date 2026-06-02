## Handles traps, faults, timer interrupts, and user panic logging.
import ../../arch/riscv64/arch
import ../../lib/types
import ../../lib/syscall_types
import ../syscall/system/trap_ops
import ../dev/console
import ../fs/fs
import ../task/process
import ../trap/syscall
import ../trap/trap_types

when not defined(milkvBringup):
  import ../dev/timer

when defined(platformMilkVDuo256m):
  import ../../platform/milkv_duo256m/memory_layout

const
  UserPanicLogPath = cstring"/var/log/user_panic.log"
  UserPanicLogMax = 512

  ScauseInstructionAddressMisaligned   = U64(0x00)
  ScauseInstructionAccessFault          = U64(0x01)
  ScauseIllegalInstruction              = U64(0x02)
  ScauseBreakpoint                      = U64(0x03)
  ScauseLoadAddressMisaligned           = U64(0x04)
  ScauseLoadAccessFault                 = U64(0x05)
  ScauseStoreAMOAddressMisaligned       = U64(0x06)
  ScauseStoreAMOAccessFault             = U64(0x07)
  ScauseEnvironmentCallFromUMode        = U64(0x08)
  ScauseEnvironmentCallFromSMode        = U64(0x09)
  ScauseInstructionPageFault            = U64(0x0c)
  ScauseLoadPageFault                   = U64(0x0d)
  ScauseStoreAMOPageFault               = U64(0x0f)
  ScauseInterruptFlag                   = U64(1) shl 63
  ScauseSupervisorTimer                 = ScauseInterruptFlag or U64(0x05)

when defined(milkvBringup):
  var
    milkvTimerInterruptCount* {.volatile.}: U64
    milkvLastTimerScause* {.volatile.}: U64
    milkvLastTimerSepc* {.volatile.}: U64


  proc sbiSetTimer(value: U64) {.importc: "sbi_set_timer", cdecl.}


## Implements the trap from user kernel helper.
proc trapFromUser(frame: ptr TrapFrame): bool =
  (frame.sstatus and SstatusSpp) == U64(0)


## Implements the panic msg kernel helper.
proc panicMsg(scauseType: cstring, scause: U64, stval: U64, userPc: U64) =
  print("PANIC: ")
  print(scauseType)
  print(". scause=")
  printPtr(scause)
  print(", stval=")
  printPtr(stval)
  print(", sepc=")
  printPtr(userPc)
  putChar('\n')
  while true:
    arch.wfi()


## Appends log char.
proc appendLogChar(dst: var array[UserPanicLogMax, char], pos: var U64, ch: char) =
  if pos + U64(1) >= U64(UserPanicLogMax):
    return

  dst[pos] = ch
  inc pos
  dst[pos] = '\0'


## Appends log cstring.
proc appendLogCString(dst: var array[UserPanicLogMax, char], pos: var U64, src: cstring) =
  if src == nil:
    appendLogCString(dst, pos, cstring"(nil)")
    return

  var i = U64(0)
  while src[i] != '\0' and pos + U64(1) < U64(UserPanicLogMax):
    dst[pos] = src[i]
    inc pos
    inc i
  dst[pos] = '\0'


## Appends log unsigned.
proc appendLogUnsigned(dst: var array[UserPanicLogMax, char], pos: var U64, value: U64) =
  var digits: array[20, char]
  var n = value
  var count = 0

  if n == U64(0):
    appendLogChar(dst, pos, '0')
    return

  while n > U64(0) and count < digits.len:
    digits[count] = char(ord('0') + int(n mod U64(10)))
    n = n div U64(10)
    inc count

  while count > 0:
    dec count
    appendLogChar(dst, pos, digits[count])


## Implements the log hex digit kernel helper.
proc logHexDigit(value: U64): char =
  let digit = int(value and U64(0xf))
  if digit < 10:
    char(ord('0') + digit)
  else:
    char(ord('a') + digit - 10)


## Appends log hex.
proc appendLogHex(dst: var array[UserPanicLogMax, char], pos: var U64, value: U64) =
  appendLogCString(dst, pos, cstring"0x")

  var started = false
  var shift = 60
  while shift >= 0:
    let digit = (value shr U64(shift)) and U64(0xf)
    if digit != U64(0) or started or shift == 0:
      appendLogChar(dst, pos, logHexDigit(digit))
      started = true
    shift -= 4


## Appends log field.
proc appendLogField(dst: var array[UserPanicLogMax, char], pos: var U64, name: cstring) =
  if pos > U64(0):
    appendLogChar(dst, pos, ' ')
  appendLogCString(dst, pos, name)
  appendLogChar(dst, pos, '=')


## Writes user panic log.
proc writeUserPanicLog(scause: U64, stval: U64, userPc: U64, frame: ptr TrapFrame) =
  if currentProc == nil or frame == nil:
    return

  var line: array[UserPanicLogMax, char]
  var pos = U64(0)

  appendLogField(line, pos, cstring"pid")
  appendLogUnsigned(line, pos, U64(currentProc.pid))
  appendLogField(line, pos, cstring"exe")
  appendLogCString(line, pos, currentProc.exePath)
  appendLogField(line, pos, cstring"scause")
  appendLogHex(line, pos, scause)
  appendLogField(line, pos, cstring"stval")
  appendLogHex(line, pos, stval)
  appendLogField(line, pos, cstring"sepc")
  appendLogHex(line, pos, userPc)
  appendLogField(line, pos, cstring"sp")
  appendLogHex(line, pos, frame.sp)
  appendLogField(line, pos, cstring"a0")
  appendLogHex(line, pos, frame.a0)
  appendLogField(line, pos, cstring"a1")
  appendLogHex(line, pos, frame.a1)
  appendLogField(line, pos, cstring"a2")
  appendLogHex(line, pos, frame.a2)
  appendLogField(line, pos, cstring"a3")
  appendLogHex(line, pos, frame.a3)
  appendLogChar(line, pos, '\n')

  discard fsWriteFileWithFlags(
    UserPanicLogPath,
    addr line[0],
    pos,
    SysFsWriteCreate or SysFsWriteAppend,
  )


## Implements the fault or panic kernel helper.
proc faultOrPanic(scauseType: cstring, scause: U64, stval: U64, userPc: U64, fromUser: bool, frame: ptr TrapFrame) =
  if fromUser and currentProc != nil:
    print("PAGE FAULT DETECTED: ")
    print(scauseType)
    print(". scause=")
    printPtr(scause)
    print(", stval=")
    printPtr(stval)
    print(", sepc=")
    printPtr(userPc)
    putChar('\n')
    writeUserPanicLog(scause, stval, userPc, frame)
    killCurrentUserProcess(U64(255))
  else:
    panicMsg(scauseType, scause, stval, userPc)


## Handles one trap or interrupt from machine state.
proc trapHandler*(frame: ptr TrapFrame) {.exportc: "trap_handler", cdecl.} =
  discard frame

  let scause = arch.readScause()
  let stval = arch.readStval()
  let userPc = frame.sepc

  let fromUser = trapFromUser(frame)

  case scause
  of ScauseInstructionAddressMisaligned:
    inc trapCount.instructionAddressMissaligned
    faultOrPanic("Instruction Address Misaligned", scause, stval, userPc, fromUser, frame)

  of ScauseInstructionAccessFault:
    inc trapCount.instructionAccessFault
    faultOrPanic("Instruction Access Fault", scause, stval, userPc, fromUser, frame)

  of ScauseIllegalInstruction:
    inc trapCount.illegalInstruction
    faultOrPanic("Illegal Instruction", scause, stval, userPc, fromUser, frame)
  
  of ScauseBreakpoint:
    inc trapCount.breakpoint
    faultOrPanic("Breakpoint", scause, stval, userPc, fromUser, frame)
  
  of ScauseLoadAddressMisaligned:
    inc trapCount.loadAddressMisaligned
    faultOrPanic("Load Address Misaligned", scause, stval, userPc, fromUser, frame)
  
  of ScauseLoadAccessFault:
    inc trapCount.loadAccessFault
    faultOrPanic("Load Access Fault", scause, stval, userPc, fromUser, frame)
  
  of ScauseStoreAMOAddressMisaligned:
    inc trapCount.storeAMOAddressMisaligned
    faultOrPanic("Store/AMO Address Misaligned", scause, stval, userPc, fromUser, frame)
  
  of ScauseStoreAMOAccessFault:
    inc trapCount.storeAMOAccessFault
    faultOrPanic("Store/AMO Access Fault", scause, stval, userPc, fromUser, frame)
  
  of ScauseEnvironmentCallFromUMode:
    inc trapCount.environmentCallFromUMode
    handleSyscall(frame)
    frame.sepc = userPc + 4
    deliverCurrentSignals()
    maybeYieldOnResched()
  
  of ScauseEnvironmentCallFromSMode:
    inc trapCount.environmentCallFromSMode
    panicMsg("Environment Call from S-Mode", scause, stval, userPc)
  
  of ScauseInstructionPageFault:
    inc trapCount.instructionPageFault
    faultOrPanic("Instruction Page Fault", scause, stval, userPc, fromUser, frame)
  
  of ScauseLoadPageFault:
    inc trapCount.loadPageFault
    faultOrPanic("Load Page Fault", scause, stval, userPc, fromUser, frame)
  
  of ScauseStoreAMOPageFault:
    inc trapCount.storeAMOPageFault
    faultOrPanic("Store/AMO Page Fault", scause, stval, userPc, fromUser, frame)
  
  of ScauseSupervisorTimer:
    when defined(milkvBringup):
      inc trapCount.supervisorTimer
      inc milkvTimerInterruptCount
      milkvLastTimerScause = scause
      milkvLastTimerSepc = userPc
      sbiSetTimer(arch.rdtime() + MilkvTimerInterruptDelta)
    else:
      inc trapCount.supervisorTimer
      countUpTimerTick()
      countCurrentProcessCpuTick()
      if currentIsIdleProcess():
        countUpIdleTick()
      if cpuWindowReady():
        snapshotProcessCpuWindow(cpuWindowTickCount)
        snapshotCpuWindow()
      wakeTimerWaiters(timerTickCount)

      if pollInput():
        wakeInputWaiters()

      setNextTimer()

      requestResched()
      if fromUser:
        deliverCurrentSignals()
        maybeYieldOnResched()
  
  else:
    panicMsg("Unexpected Trap", scause, stval, userPc)
