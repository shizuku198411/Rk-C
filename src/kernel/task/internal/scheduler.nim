## Runs process entry trampolines and performs scheduling and CPU yields.

## Runs the initial trampoline for a newly scheduled process.
proc processBootstrap*() =
  if currentProc == nil or currentProc.entry == nil:
    panic("invalid current process")

  currentProc.entry()
  currentProc.state = procZombie
  schedule()
  panic("zombie process resumed")


## Returns the effective root page table for a process.
proc effectiveRootPageTable(p: ptr Process): PageTable =
  if p != nil and p.rootPageTable != nil:
    return p.rootPageTable

  kernelPageTable


## Returns true when the process can continue running without a context switch.
proc canContinueRunning(p: ptr Process): bool =
  p != nil and (p.state == procRunning or p.state == procRunnable)


## Selects the next runnable process and switches to it.
proc schedule*() =
  let prev = currentProc
  var start = 0
  var next: ptr Process = nil

  reapDetachedZombies()

  if currentProc != nil:
    let currentIndex =
      (cast[U64](currentProc) - cast[U64](addr procs[0])) div U64(sizeof(Process))
    start = int((currentIndex + 1'u64) mod U64(MaxProcs))

  var i = 0
  while i < MaxProcs:
    let idx = (start + i) mod MaxProcs
    let candidate = addr procs[idx]

    if candidate != idleProc and candidate.state == procRunnable:
      next = candidate
      break

    inc i

  if next == nil and idleProc != nil and
      (idleProc.state == procRunnable or idleProc.state == procRunning):
    next = idleProc

  if next == nil:
    if canContinueRunning(prev):
      prev.state = procRunning
      currentProc = prev
      return

    panic("no runnable process")

  ##
  ## Fast path:
  ## If the scheduler selected the currently running process again, there is no
  ## context switch and no address-space switch.  Avoid rewriting satp and
  ## flushing the TLB.
  ##
  ## This matters when timer interrupts request reschedule but no other process
  ## is runnable, or when scheduling returns to the same task.
  ##
  if prev == next:
    next.state = procRunning
    currentProc = next
    needResched = false
    return

  let prevRoot = effectiveRootPageTable(prev)
  let nextRoot = effectiveRootPageTable(next)

  next.state = procRunning
  currentProc = next
  needResched = false

  ##
  ## Only switch address spaces when the effective root page table actually
  ## changes.
  ##
  ## Kernel processes normally share kernelPageTable, so kernel->kernel switches
  ## can avoid satp writes and TLB flushes.
  ##
  if nextRoot != nil and nextRoot != prevRoot:
    arch.writeSatp(makeSatp(cast[PAddr](nextRoot)))
    paging.flushTlb()

  arch.writeSscratch(next.kernelStack + KernelStackPages * PageSize)

  if prev == nil:
    var dummy = Context()
    contextSwitch(addr dummy, addr next.context)
  else:
    contextSwitch(addr prev.context, addr next.context)


## Yields the current process to the scheduler.
proc yieldCpu*() =
  if currentProc == nil and not hasRunnableProcess():
    return

  if currentProc != nil and currentProc.state == procRunning:
    currentProc.state = procRunnable

  schedule()