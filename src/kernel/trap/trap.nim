import ../../arch/riscv64/arch
import ../../lib/types
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


proc trapHandler*(frame: ptr TrapFrame) {.exportc: "trap_handler", cdecl.} =
  discard frame

  let scause = arch.readScause()
  let stval = arch.readStval()
  let userPc = arch.readSepc()

  case scause
  of ScauseInstructionAddressMMisaligned:
    panicMsg("Instruction Address Misaligned", scause, stval, userPc)

  of ScauseInstructionAccessFault:
    panicMsg("Instruction Access Fault", scause, stval, userPc)

  of ScauseIllegalInstruction:
    panicMsg("Illegal Instruction", scause, stval, userPc)
  
  of ScauseBreakpoint:
    panicMsg("Breakpoint", scause, stval, userPc)
  
  of ScauseLoadAddressMisaligned:
    panicMsg("Load Address Misaligned", scause, stval, userPc)
  
  of ScauseLoadAccessFault:
    panicMsg("Load Access Fault", scause, stval, userPc)
  
  of ScauseStoreAMOAddressMisaligned:
    panicMsg("Store/AMO Address Misaligned", scause, stval, userPc)
  
  of ScauseStoreAMOAccessFault:
    panicMsg("Store/AMO Access Fault", scause, stval, userPc)
  
  of ScauseEnvironmentCallFromUMode:
    handleSyscall(frame)
    arch.writeSepc(userPc + 4)
  
  of ScauseEnvironmentCallFromSMode:
    panicMsg("Environment Call from S-Mode", scause, stval, userPc)
  
  of ScauseInstructionPageFault:
    panicMsg("Instruction Page Fault", scause, stval, userPc)
  
  of ScauseLoadPageFault:
    panicMsg("Load Page Fault", scause, stval, userPc)
  
  of ScauseStoreAMOPageFault:
    panicMsg("Store/AMO Page Fault", scause, stval, userPc)
  
  of ScauseSupervisorTimer:
    countUpTimerTick()
    wakeTimerWaiters(timerTickCount)
    if pollInput():
      wakeInputWaiters()
    setNextTimer()
    requestResched()
    arch.writeSepc(userPc)
  
  else:
    panicMsg("Unexpected Trap", scause, stval, userPc)
