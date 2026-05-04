import ../arch/riscv64/arch
import ../kernel/console
import ../kernel/fs/fs
import ../kernel/memory
import ../kernel/paging
import ../kernel/process
import ../kernel/timer
import ../kernel/rtc
import ../lib/mem
import ../lib/types

const
  QemuUart0Base = PAddr(0x10000000)
  QemuMmioSize = U64(0x00010000)
  QemuPlicBase = PAddr(0x0c000000)
  QemuPlicSize = U64(0x00400000)
  QemuRtcBase = PAddr(0x00101000)
  QemuRtcSize = U64(0x00001000)

var
  bssStartSym {.importc: "__bss_start".}: char
  bssEndSym {.importc: "__bss_end".}: char
  kernelBaseSym {.importc: "__kernel_base".}: char
  kernelEndSym {.importc: "__kernel_end".}: char
  stackBottomSym {.importc: "__stack_bottom".}: char
  stackTopSym {.importc: "__stack_top".}: char
  freeRamStartSym {.importc: "__free_ram_start".}: char
  freeRamEndSym {.importc: "__free_ram_end".}: char
  kernelRootPageTable: PageTable

proc clearBss() =
  let start = cast[U64](addr bssStartSym)
  let last = cast[U64](addr bssEndSym)
  let size = last - start
  zeroMem(cast[pointer](start), size)

  if not isZeroed(cast[pointer](start), size):
    panic("failed to bss zero clear")

proc setTrapVector() =
  arch.writeStvec(cast[U64](arch.trapEntry))

proc enableTimerInterrupt() =
  arch.writeSie(arch.readSie() or SieStie)
  arch.writeSstatus(arch.readSstatus() or SstatusSie or SstatusSum)

proc enableSv39(memInfo: MemoryInfo) =
  kernelRootPageTable = allocPageTable()
  if kernelRootPageTable == nil:
    panic("failed to allocate kernel root page table")

  let kernelMapStart = cast[VAddr](addr kernelBaseSym) and not (PageSize - 1'u64)
  let kernelMapSize = alignUp(cast[U64](addr freeRamEndSym) - kernelMapStart, PageSize)

  if mapRange(kernelRootPageTable, kernelMapStart, kernelMapStart, kernelMapSize, PteR or PteW or PteX) != 0:
    panic("failed to map kernel identity range")

  if mapRange(kernelRootPageTable, QemuUart0Base, QemuUart0Base, QemuMmioSize, PteR or PteW) != 0:
    panic("failed to map qemu mmio")

  if mapRange(kernelRootPageTable, QemuPlicBase, QemuPlicBase, QemuPlicSize, PteR or PteW) != 0:
    panic("failed to map plic mmio")
  
  if mapRange(kernelRootPageTable, QemuRtcBase, QemuRtcBase, QemuRtcSize, PteR or PteW) != 0:
    panic("faile to map rtc mmio")

  let satp = makeSatp(cast[PAddr](kernelRootPageTable))
  paging.flushTlb()
  arch.writeSatp(satp)
  paging.flushTlb()

  discard memInfo

proc addressInfo(hartid: U64, dtb: pointer, memInfo: MemoryInfo) =
  let bssSize = cast[U64](addr bssEndSym) - cast[U64](addr bssStartSym)
  let freeRamSize = cast[U64](addr freeRamEndSym) - cast[U64](addr freeRamStartSym)

  putChar('\n')
  printBootMsg("hartid       = ")
  printUnsigned(hartid)
  putChar('\n')
  
  printBootMsg("dtb          = ")
  printPtr(cast[U64](dtb))
  putChar('\n')

  printBootMsg("bss start    = ")
  printPtr(cast[U64](addr bssStartSym))
  putChar('\n')
  printBootMsg("bss end      = ")
  printPtr(cast[U64](addr bssEndSym))
  putChar('\n')
  printBootMsg("bss size     = ")
  printUnsigned(bssSize)
  println(" bytes")

  printBootMsg("kernel base  = ")
  printPtr(cast[U64](addr kernelBaseSym))
  putChar('\n')
  printBootMsg("kernel end   = ")
  printPtr(cast[U64](addr kernelEndSym))
  putChar('\n')

  printBootMsg("stack bottom = ")
  printPtr(cast[U64](addr stackBottomSym))
  putChar('\n')
  printBootMsg("stack top    = ")
  printPtr(cast[U64](addr stackTopSym))
  putChar('\n')
  putChar('\n')

  printBootMsg("free ram             = ")
  printPtr(cast[U64](addr freeRamStartSym))
  print(" - ")
  printPtr(cast[U64](addr freeRamEndSym))
  putChar('\n')
  printBootMsg("free ram size        = ")
  printUnsigned(freeRamSize)
  println(" bytes")
  printBootMsg("managed region start = ")
  printPtr(memInfo.managedRegionStart)
  putChar('\n')
  printBootMsg("total bitmap page    = ")
  printUnsigned(memInfo.bitmapPageCount)
  putChar('\n')
  printBootMsg("total managed page   = ")
  printUnsigned(memInfo.managedPageCount)
  putChar('\n')
  printBootMsg("kernel root pt       = ")
  printPtr(cast[U64](kernelRootPageTable))
  putChar('\n')

proc kernelBootstrap*(hartid: U64, dtb: pointer) =
  putChar('\n')
  printBootMsg("starting kernel bootstrap\n")

  printBootMsg("  start time: ")
  print(nowCString())
  print("\n\n")

  printBootMsg("clear bss ")
  clearBss()
  println("OK")

  printBootMsg("set trap vector ")
  setTrapVector()
  println("OK")

  printBootMsg("enable timer interrupt ")
  enableTimerInterrupt()
  setNextTimer()
  println("OK")

  printBootMsg("initialize memory allocator ")
  let memInfo = memoryInit()
  println("OK")

  printBootMsg("initialize process ")
  processInit()
  println("OK")

  printBootMsg("enable Sv39 ")
  enableSv39(memInfo)
  println("OK")

  fsInit()
  addressInfo(hartid, dtb, memInfo)

  putChar('\n')
  printBootMsg("kernel bootstrap completed\n")
  printBootMsg("  end time: ")
  print(nowCString())
  putChar('\n')

proc getKernelRootPageTable*(): PageTable =
  kernelRootPageTable
