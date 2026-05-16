import ../../arch/riscv64/arch
import ../../lib/types
import ../../lib/syscall_types
import ../syscall/system/trap_ops
import ../dev/console
import ../dev/timer
import ../task/process
import ../trap/syscall
import ../trap/trap_types

const
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


proc trapFromUser(frame: ptr TrapFrame): bool =
  (frame.sstatus and SstatusSpp) == U64(0)


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


proc faultOrPanic(scauseType: cstring, scause: U64, stval: U64, userPc: U64, fromUser: bool) =
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
    killCurrentUserProcess(U64(255))
  else:
    panicMsg(scauseType, scause, stval, userPc)


proc trapHandler*(frame: ptr TrapFrame) {.exportc: "trap_handler", cdecl.} =
  discard frame

  let scause = arch.readScause()
  let stval = arch.readStval()
  let userPc = frame.sepc

  let fromUser = trapFromUser(frame)

  case scause
  of ScauseInstructionAddressMisaligned:
    inc trapCount.instructionAddressMissaligned
    faultOrPanic("Instruction Address Misaligned", scause, stval, userPc, fromUser)

  of ScauseInstructionAccessFault:
    inc trapCount.instructionAccessFault
    faultOrPanic("Instruction Access Fault", scause, stval, userPc, fromUser)

  of ScauseIllegalInstruction:
    inc trapCount.illegalInstruction
    faultOrPanic("Illegal Instruction", scause, stval, userPc, fromUser)
  
  of ScauseBreakpoint:
    inc trapCount.breakpoint
    faultOrPanic("Breakpoint", scause, stval, userPc, fromUser)
  
  of ScauseLoadAddressMisaligned:
    inc trapCount.loadAddressMisaligned
    faultOrPanic("Load Address Misaligned", scause, stval, userPc, fromUser)
  
  of ScauseLoadAccessFault:
    inc trapCount.loadAccessFault
    faultOrPanic("Load Access Fault", scause, stval, userPc, fromUser)
  
  of ScauseStoreAMOAddressMisaligned:
    inc trapCount.storeAMOAddressMisaligned
    faultOrPanic("Store/AMO Address Misaligned", scause, stval, userPc, fromUser)
  
  of ScauseStoreAMOAccessFault:
    inc trapCount.storeAMOAccessFault
    faultOrPanic("Store/AMO Access Fault", scause, stval, userPc, fromUser)
  
  of ScauseEnvironmentCallFromUMode:
    inc trapCount.environmentCallFromUMode
    handleSyscall(frame)
    frame.sepc = userPc + 4
    maybeYieldOnResched()
  
  of ScauseEnvironmentCallFromSMode:
    inc trapCount.environmentCallFromSMode
    panicMsg("Environment Call from S-Mode", scause, stval, userPc)
  
  of ScauseInstructionPageFault:
    inc trapCount.instructionPageFault
    faultOrPanic("Instruction Page Fault", scause, stval, userPc, fromUser)
  
  of ScauseLoadPageFault:
    inc trapCount.loadPageFault
    faultOrPanic("Load Page Fault", scause, stval, userPc, fromUser)
  
  of ScauseStoreAMOPageFault:
    inc trapCount.storeAMOPageFault
    faultOrPanic("Store/AMO Page Fault", scause, stval, userPc, fromUser)
  
  of ScauseSupervisorTimer:
    inc trapCount.supervisorTimer
    countUpTimerTick()
    wakeTimerWaiters(timerTickCount)

    if pollInput():
      wakeInputWaiters()
    
    setNextTimer()

    requestResched()
    if fromUser:
      maybeYieldOnResched()
  
  else:
    panicMsg("Unexpected Trap", scause, stval, userPc)
