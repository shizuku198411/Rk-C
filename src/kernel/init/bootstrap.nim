import ../../arch/riscv64/arch
import ../../lib/mem
import ../../lib/types
import ../dev/console
import ../dev/rtc
import ../dev/timer
import ../fs/fs
import ../mm/memory
import ../mm/paging
import ../task/process

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
  textStartSym {.importc: "__text_start".}: char
  textEndSym {.importc: "__text_end".}: char
  rodataStartSym {.importc: "__rodata_start".}: char
  rodataEndSym {.importc: "__rodata_end".}: char
  dataStartSym {.importc: "__data_start".}: char
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
  arch.writeSstatus((arch.readSstatus() or SstatusSie) and not SstatusSum)


proc mapKernelRanges(root: PageTable) =
  let textStart = alignDown(cast[VAddr](addr textStartSym), PageSize)
  let textSize = alignUp(cast[U64](addr textEndSym) - textStart, PageSize)
  let rodataStart = alignDown(cast[VAddr](addr rodataStartSym), PageSize)
  let rodataSize = alignUp(cast[U64](addr rodataEndSym) - rodataStart, PageSize)
  let dataStart = alignDown(cast[VAddr](addr dataStartSym), PageSize)
  let dataSize = alignUp(cast[U64](addr freeRamEndSym) - dataStart, PageSize)

  if mapRange(root, textStart, textStart, textSize, PteR or PteX) != 0:
    panic("failed to map kernel text range")

  if mapRange(root, rodataStart, rodataStart, rodataSize, PteR) != 0:
    panic("failed to map kernel rodata range")

  if mapRange(root, dataStart, dataStart, dataSize, PteR or PteW) != 0:
    panic("failed to map kernel data range")

  if mapRange(root, QemuUart0Base, QemuUart0Base, QemuMmioSize, PteR or PteW) != 0:
    panic("failed to map qemu mmio")

  if mapRange(root, QemuPlicBase, QemuPlicBase, QemuPlicSize, PteR or PteW) != 0:
    panic("failed to map plic mmio")

  if mapRange(root, QemuRtcBase, QemuRtcBase, QemuRtcSize, PteR or PteW) != 0:
    panic("failed to map rtc mmio")


proc createKernelMappedPageTable*(): PageTable =
  let root = allocPageTable()
  if root == nil:
    return nil

  mapKernelRanges(root)
  root


proc enableSv39(memInfo: MemoryInfo) =
  kernelRootPageTable = createKernelMappedPageTable()
  if kernelRootPageTable == nil:
    panic("failed to allocate kernel root page table")

  setKernelPageTable(kernelRootPageTable)
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
