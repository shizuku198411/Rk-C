## Runs process entry trampolines and performs scheduling and CPU yields.

## Runs the initial trampoline for a newly scheduled process.
proc processBootstrap*() =
  if currentProc == nil or currentProc.entry == nil:
    panic("invalid current process")

  currentProc.entry()
  currentProc.state = procZombie
  schedule()
  panic("zombie process resumed")


## Selects the next runnable process and switches to it.
proc schedule*() =
  let prev = currentProc
  var start = 0
  var next: ptr Process = nil

  reapDetachedZombies()

  if currentProc != nil:
    let currentIndex = (cast[U64](currentProc) - cast[U64](addr procs[0])) div U64(sizeof(Process))
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
    if prev != nil and (prev.state == procRunning or prev.state == procRunnable):
      prev.state = procRunning
      currentProc = prev
      return

    panic("no runnable process")

  next.state = procRunning
  currentProc = next
  let nextRoot =
    if next.rootPageTable != nil:
      next.rootPageTable
    else:
      kernelPageTable

  if nextRoot != nil:
    arch.writeSatp(makeSatp(cast[PAddr](nextRoot)))
    paging.flushTlb()

  arch.writeSscratch(next.kernelStack + KernelStackPages * PageSize)

  if prev == next:
    return

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
