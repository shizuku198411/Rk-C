## Runs Milk-V Phase 6 scheduler, paging, and userspace validation.
import ../../../arch/riscv64/arch
import ../../../lib/syscall_ids
import ../../../lib/types
import ../../dev/console
import ../../mm/memory
import ../../mm/paging
import ../../task/exec
import ../../task/process
import ../../trap/trap
import ../runtime_setup
import ./shared

const
  MilkvEmbeddedUserMessageLen = U64(27)

var
  milkvBssProbe: U64
  milkvSupervisorStarted: bool
  milkvEmbeddedUserDone: bool


## Checks BSS and current stack placement before restoring runtime state.
proc runMilkvPhase6BssStackChecks(): bool =
  var stackProbe: U64
  let stackAddr = cast[U64](addr stackProbe)
  let stackBottom = cast[U64](addr stackBottomSym)
  let stackTop = cast[U64](addr stackTopSym)
  var ok = true

  if milkvBssProbe == U64(0):
    printMilkvStatus("bss zero", "OK")
  else:
    printMilkvStatus("bss zero", "FAIL")
    ok = false

  if stackAddr >= stackBottom and stackAddr < stackTop:
    printMilkvStatus("stack range", "OK")
  else:
    printMilkvStatus("stack range", "FAIL")
    ok = false

  printMilkvHex("  stack probe", stackAddr)
  printMilkvStatus("panic diagnostics", "READY")
  ok


## Runs allocator checks after earlier smoke tests have completed.
proc runMilkvPhase6AllocatorRuntimeCheck(): bool =
  let before = bitmapInfo()
  printMilkvPrefix()
  printlnConsoleOnly("allocator runtime:")
  printMilkvUnsigned("  total pages", before.total)
  printMilkvUnsigned("  used pages ", before.used)
  printMilkvUnsigned("  free pages ", before.free)

  let pageCount = U64(4)
  let pages = palloc(pageCount)
  if pages == NilPAddr:
    printMilkvStatus("allocator runtime", "FAIL")
    return false

  let afterAlloc = bitmapInfo()
  discard pfree(pages, pageCount)
  let afterFree = bitmapInfo()
  if afterAlloc.used == before.used + pageCount and
      afterFree.used == before.used and afterFree.free == before.free:
    printMilkvStatus("allocator runtime", "OK")
    return true

  printMilkvStatus("allocator runtime", "FAIL")
  false


## Enables the shared kernel Sv39 mapping for Milk-V runtime restore checks.
proc runMilkvPhase6PagingCheck(): bool =
  printMilkvPrefix()
  printlnConsoleOnly("paging:")
  let before = arch.readSatp()
  kernelRootPageTable = createKernelMappedPageTable()
  if kernelRootPageTable == nil:
    printMilkvStatus("sv39 identity map", "FAIL")
    return false

  setKernelPageTable(kernelRootPageTable)
  let satp = makeSatp(cast[PAddr](kernelRootPageTable))
  printMilkvHex("  root page table", cast[U64](kernelRootPageTable))
  printMilkvHex("  satp before", before)
  paging.flushTlb()
  arch.writeSatp(satp)
  paging.flushTlb()
  printMilkvHex("  satp after ", arch.readSatp())

  if arch.readSatp() == satp and arch.readSatp() != U64(0):
    printMilkvStatus("sv39 identity map", "OK")
    return true

  printMilkvStatus("sv39 identity map", "FAIL")
  false


## Writes one U32 instruction into an embedded user text page.
proc writeMilkvUserInsn(text: ptr UncheckedArray[U32], index: U64, value: U32) =
  text[index] = value


## Encodes one RISC-V addi instruction with a small positive immediate.
proc encodeMilkvAddi(rd, rs1: U32, imm: U32): U32 =
  ((imm and U32(0xfff)) shl 20) or
    ((rs1 and U32(0x1f)) shl 15) or
    ((rd and U32(0x1f)) shl 7) or
    U32(0x13)


## Copies the embedded user task message into its rodata page.
proc writeMilkvUserMessage(rodata: ptr UncheckedArray[char]) =
  let msg = cstring"hello from milkv user task\n"
  var i = U64(0)
  while i < MilkvEmbeddedUserMessageLen:
    rodata[i] = msg[i]
    inc i
  rodata[i] = '\0'


## Creates a tiny U-mode program that writes to stdout and exits.
proc createMilkvEmbeddedUserTask(): int32 =
  let p = allocUserProcessFromParent(currentProc)
  if p == nil:
    return -1

  let root = createKernelMappedPageTable()
  if root == nil:
    discardProcess(p)
    return -1

  let textPa = palloc(U64(1))
  let rodataPa = palloc(U64(1))
  let stackPa = palloc(U64(1))
  if textPa == NilPAddr or rodataPa == NilPAddr or stackPa == NilPAddr:
    if textPa != NilPAddr:
      discard pfree(textPa, U64(1))
    if rodataPa != NilPAddr:
      discard pfree(rodataPa, U64(1))
    if stackPa != NilPAddr:
      discard pfree(stackPa, U64(1))
    freePageTablePages(root)
    discardProcess(p)
    return -1

  zeroMem(cast[pointer](textPa), PageSize)
  zeroMem(cast[pointer](rodataPa), PageSize)
  zeroMem(cast[pointer](stackPa), PageSize)

  let text = cast[ptr UncheckedArray[U32]](textPa)
  writeMilkvUserInsn(text, U64(0), U32(0x01201537)) # lui a0, 0x1201
  writeMilkvUserInsn(text, U64(1), encodeMilkvAddi(U32(11), U32(0), U32(MilkvEmbeddedUserMessageLen)))
  writeMilkvUserInsn(text, U64(2), encodeMilkvAddi(U32(13), U32(0), U32(SysWrite)))
  writeMilkvUserInsn(text, U64(3), U32(0x00000073)) # ecall
  writeMilkvUserInsn(text, U64(4), encodeMilkvAddi(U32(10), U32(0), U32(0)))
  writeMilkvUserInsn(text, U64(5), encodeMilkvAddi(U32(13), U32(0), U32(SysExit)))
  writeMilkvUserInsn(text, U64(6), U32(0x00000073)) # ecall
  writeMilkvUserInsn(text, U64(7), U32(0x00100073)) # ebreak if exit fails
  writeMilkvUserMessage(cast[ptr UncheckedArray[char]](rodataPa))

  let textVa = AppBase
  let rodataVa = AppBase + PageSize
  let stackTop = AppStackTop
  let stackVa = stackTop - PageSize
  if mapPage(root, textVa, textPa, PteR or PteX or PteU) != 0 or
      mapPage(root, rodataVa, rodataPa, PteR or PteU) != 0 or
      mapPage(root, stackVa, stackPa, PteR or PteW or PteU) != 0:
    freePageTablePages(root)
    discardProcess(p)
    return -1

  configureUserProcess(
    p,
    root,
    cstring"milkv_embedded_user",
    AppBase,
    textVa,
    stackTop,
    stackTop,
    U64(2),
    U64(1),
  )
  setUserRkxMap(p, textVa, PageSize, rodataVa, PageSize, U64(0), U64(0), U64(0), U64(0))
  p.pid


## Waits for the embedded user task to exit and reports its status.
proc waitForMilkvEmbeddedUserTask(pid: int32): bool =
  var loops = U64(0)
  var target = findProcessByPid(pid)
  while target != nil and target.state != procZombie and loops < U64(8):
    yieldCpu()
    target = findProcessByPid(pid)
    inc loops

  if target == nil or target.state != procZombie:
    printMilkvStatus("syscall exit", "FAIL")
    return false

  printMilkvUnsigned("  user exit status", target.exitStatus)
  let ok = target.exitStatus == U64(0)
  discardProcess(target)
  if ok:
    printMilkvStatus("syscall exit", "OK")
  else:
    printMilkvStatus("syscall exit", "FAIL")

  ok


## Runs inside the first scheduled kernel process for Phase 6 runtime checks.
proc milkvPhase6SupervisorTask() {.cdecl.} =
  milkvSupervisorStarted = true
  printMilkvStatus("context switch", "OK")

  let start = milkvTimerInterruptCount
  while milkvTimerInterruptCount < start + U64(2):
    arch.wfi()
  printMilkvUnsigned("  timer count", milkvTimerInterruptCount)
  printMilkvStatus("scheduler timer source", "OK")

  let pid = createMilkvEmbeddedUserTask()
  if pid < 0:
    printMilkvStatus("embedded user task", "FAIL")
    enterBringupLoop()

  printMilkvUnsigned("  user pid", U64(pid))
  printMilkvStatus("embedded user task", "OK")
  if waitForMilkvEmbeddedUserTask(pid):
    printMilkvStatus("syscall write", "OK")
    milkvEmbeddedUserDone = true
    printMilkvStatus("phase6 runtime restore", "OK")
  else:
    printMilkvStatus("phase6 runtime restore", "FAIL")

  enterBringupLoop()


## Restores core Rk-C runtime pieces far enough to run a tiny user process.
proc runMilkvPhase6Checks*() =
  printlnConsoleOnly("")
  printlnConsoleOnly("[milkv] phase6 runtime restore checks")
  printMilkvStatus("qemu drivers", "SKIP")
  printMilkvStatus("runtime mode", "minimal")

  if not runMilkvPhase6BssStackChecks():
    printMilkvStatus("phase6 runtime restore", "FAIL")
    return

  if not runMilkvPhase6AllocatorRuntimeCheck():
    printMilkvStatus("phase6 runtime restore", "FAIL")
    return

  processInit()
  let idle = findProcessByPid(1)
  if idle != nil and idle.state == procRunnable:
    printMilkvStatus("process table", "OK")
    printMilkvUnsigned("  idle task pid", U64(idle.pid))
  else:
    printMilkvStatus("process table", "FAIL")
    printMilkvStatus("phase6 runtime restore", "FAIL")
    return

  if not runMilkvPhase6PagingCheck():
    printMilkvStatus("phase6 runtime restore", "FAIL")
    return

  let supervisorPid = createKernelProcessNamed(milkvPhase6SupervisorTask, "milkv_phase6")
  if supervisorPid < 0:
    printMilkvStatus("phase6 supervisor", "FAIL")
    printMilkvStatus("phase6 runtime restore", "FAIL")
    return

  printMilkvUnsigned("  supervisor pid", U64(supervisorPid))
  printMilkvStatus("phase6 supervisor", "OK")
  schedule()

  if not milkvSupervisorStarted or not milkvEmbeddedUserDone:
    printMilkvStatus("phase6 scheduler return", "WARN")
