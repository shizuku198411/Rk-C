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
  ScauseInstructionAddressMMisaligned   = U64(0x00)
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


proc faultOrPanic(scauseType: cstring, scause: U64, stval: U64, userPc: U64) =
  if currentProc != nil and currentProc.user.active:
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
  let userPc = arch.readSepc()

  case scause
  of ScauseInstructionAddressMMisaligned:
    inc trapCount.instructionAddressMissaligned
    panicMsg("Instruction Address Misaligned", scause, stval, userPc)

  of ScauseInstructionAccessFault:
    inc trapCount.instructionAccessFault
    panicMsg("Instruction Access Fault", scause, stval, userPc)

  of ScauseIllegalInstruction:
    inc trapCount.illegalInstruction
    faultOrPanic("Illegal Instruction", scause, stval, userPc)
  
  of ScauseBreakpoint:
    inc trapCount.breakpoint
    panicMsg("Breakpoint", scause, stval, userPc)
  
  of ScauseLoadAddressMisaligned:
    inc trapCount.loadAddressMisaligned
    panicMsg("Load Address Misaligned", scause, stval, userPc)
  
  of ScauseLoadAccessFault:
    inc trapCount.loadAccessFault
    panicMsg("Load Access Fault", scause, stval, userPc)
  
  of ScauseStoreAMOAddressMisaligned:
    inc trapCount.storeAMOAddressMisaligned
    panicMsg("Store/AMO Address Misaligned", scause, stval, userPc)
  
  of ScauseStoreAMOAccessFault:
    inc trapCount.storeAMOAccessFault
    panicMsg("Store/AMO Access Fault", scause, stval, userPc)
  
  of ScauseEnvironmentCallFromUMode:
    inc trapCount.environmentCallFromUMode
    handleSyscall(frame)
    arch.writeSepc(userPc + 4)
  
  of ScauseEnvironmentCallFromSMode:
    inc trapCount.environmentCallFromSMode
    panicMsg("Environment Call from S-Mode", scause, stval, userPc)
  
  of ScauseInstructionPageFault:
    inc trapCount.instructionPageFault
    panicMsg("Instruction Page Fault", scause, stval, userPc)
  
  of ScauseLoadPageFault:
    inc trapCount.loadPageFault
    faultOrPanic("Load Page Fault", scause, stval, userPc)
  
  of ScauseStoreAMOPageFault:
    inc trapCount.storeAMOPageFault
    faultOrPanic("Store/AMO Page Fault", scause, stval, userPc)
  
  of ScauseSupervisorTimer:
    inc trapCount.supervisorTimer
    countUpTimerTick()
    wakeTimerWaiters(timerTickCount)
    if pollInput():
      wakeInputWaiters()
    setNextTimer()
    requestResched()
    arch.writeSepc(userPc)
  
  else:
    panicMsg("Unexpected Trap", scause, stval, userPc)
