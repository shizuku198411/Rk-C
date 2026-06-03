## Provides QEMU virt timer programming.
import ../../arch/riscv64/arch
import ../../lib/types


## Programs the next supervisor timer interrupt.
proc setNextTimer*(next: U64) =
  arch.writeStimecmp(next)
