import ../../lib/types

const
  SieStie* = U64(1 shl 5)
  SstatusSie* = U64(1 shl 1)
  SstatusSum* = U64(1 shl 18)


proc wfi*() {.importc: "arch_wfi", cdecl.}
proc readScause*(): U64 {.importc: "arch_read_scause", cdecl.}
proc readStval*(): U64 {.importc: "arch_read_stval", cdecl.}
proc readSepc*(): U64 {.importc: "arch_read_sepc", cdecl.}
proc readSie*(): U64 {.importc: "arch_read_sie", cdecl.}
proc writeSie*(value: U64) {.importc: "arch_write_sie", cdecl.}
proc readSstatus*(): U64 {.importc: "arch_read_sstatus", cdecl.}
proc writeSstatus*(value: U64) {.importc: "arch_write_sstatus", cdecl.}
proc writeSepc*(value: U64) {.importc: "arch_write_sepc", cdecl.}
proc writeStvec*(value: U64) {.importc: "arch_write_stvec", cdecl.}
proc writeSscratch*(value: U64) {.importc: "arch_write_sscratch", cdecl.}
proc writeSatp*(value: U64) {.importc: "arch_write_satp", cdecl.}
proc rdtime*(): U64 {.importc: "arch_rdtime", cdecl.}
proc writeStimecmp*(value: U64) {.importc: "arch_write_stimecmp", cdecl.}
proc flushTlb*() {.importc: "arch_flush_tlb", cdecl.}
proc fenceRwRw*() {.importc: "arch_fence_rw_rw", cdecl.}
proc enterUser*(pc: U64, sp: U64, kernelSp: U64, arg0: U64, arg1: U64) {.importc: "arch_enter_user", cdecl, noreturn.}


proc trapEntry*() {.importc: "trap_entry", cdecl.}
