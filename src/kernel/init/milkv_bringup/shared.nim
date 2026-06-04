## Provides shared Milk-V bring-up constants and diagnostic output helpers.
import ../../../arch/riscv64/arch
import ../../../lib/types
import ../../dev/console
import ../runtime_setup

const
  MilkvTimerDelta* = U64(250000)


proc sbiSetTimer*(value: U64) {.importc: "sbi_set_timer", cdecl.}


## Prints one Milk-V bring-up log prefix.
proc printMilkvPrefix*() =
  printConsoleOnly("[milkv] ")


## Prints one Milk-V bring-up status line.
proc printMilkvStatus*(label: cstring, status: cstring) =
  printMilkvPrefix()
  printConsoleOnly(label)
  printConsoleOnly(" ... ")
  printlnConsoleOnly(status)


## Prints one address line for Milk-V Duo 256M bring-up mode.
proc printBringupAddress*(label: cstring, value: U64) =
  printConsoleOnly(label)
  printPtr(value)
  putChar('\n')


## Prints one Milk-V labeled hexadecimal value.
proc printMilkvHex*(label: cstring, value: U64) =
  printMilkvPrefix()
  printConsoleOnly(label)
  printConsoleOnly(" = ")
  printPtr(value)
  putChar('\n')


## Prints one Milk-V labeled decimal value.
proc printMilkvUnsigned*(label: cstring, value: U64) =
  printMilkvPrefix()
  printConsoleOnly(label)
  printConsoleOnly(" = ")
  printUnsigned(value)
  putChar('\n')


## Prints a fixed-size NUL-terminated string with a Milk-V label.
proc printMilkvFixedString*(label: cstring, value: openArray[char]) =
  printMilkvPrefix()
  printConsoleOnly(label)
  printConsoleOnly(" = ")

  var i = 0
  while i < value.len and value[i] != '\0':
    putChar(value[i])
    inc i

  if i == 0:
    printConsoleOnly("(empty)")

  putChar('\n')


## Stops the kernel in a low-noise loop after bring-up logging.
proc enterBringupLoop*() =
  printlnConsoleOnly("[milkv] entering wfi loop")
  while true:
    arch.wfi()


## Logs the current S-mode CSR snapshot for Milk-V bring-up.
proc printMilkvCsrSnapshot*() =
  printMilkvPrefix()
  printlnConsoleOnly("csr snapshot:")
  printMilkvHex("  sstatus", arch.readSstatus())
  printMilkvHex("  sie    ", arch.readSie())
  printMilkvHex("  satp   ", arch.readSatp())
  printMilkvHex("  stvec  ", arch.readStvec())
  printMilkvHex("  sscratch", arch.readSscratch())
  printMilkvHex("  scounteren", arch.readScounteren())


## Sets and verifies the trap vector without enabling interrupts.
proc checkMilkvTrapVector*() =
  setTrapVector()
  printMilkvStatus("trap vector", "OK")
  printMilkvHex("  trap_entry", cast[U64](arch.trapEntry))
  printMilkvHex("  stvec     ", arch.readStvec())


## Performs a one-shot SBI timer call while interrupts remain disabled.
proc checkMilkvTimerCall*() =
  let now = arch.rdtime()
  let next = now + MilkvTimerDelta
  printMilkvHex("  time", now)
  sbiSetTimer(next)
  printMilkvHex("  next timer", next)
  printMilkvStatus("timer call", "OK")
