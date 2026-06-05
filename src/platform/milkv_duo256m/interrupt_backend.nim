## Provides Milk-V Duo 256M PLIC and UART RX interrupt setup.
import ../../arch/riscv64/arch
import ../../kernel/dev/uart16550
import ../../lib/types
import ./memory_layout
import volatile

const
  PlicPriorityOffset = U64(0x000000)
  PlicEnableOffset = U64(0x002000)
  PlicEnableStride = U64(0x80)
  PlicContextOffset = U64(0x200000)
  PlicContextStride = U64(0x1000)
  PlicThresholdOffset = U64(0x0)
  PlicClaimOffset = U64(0x4)
  UartIer = U64(1)
  UartIir = U64(2)
  UartFcr = U64(2)
  UartLcr = U64(3)
  UartLsr = U64(5)
  UartRbr = U64(0)
  UartUsr = U64(31)
  UartIerRxAvailable = U32(1 shl 0)
  UartFcrEnable = U32(1 shl 0)
  UartFcrClearRx = U32(1 shl 1)
  UartFcrClearTx = U32(1 shl 2)
  UartLcrDlab = U32(1 shl 7)
  UartLsrDataReady = U32(1 shl 0)
  UartIirInterruptIdMask = U32(0x0f)
  UartIirBusyDetect = U32(0x07)
  UartPendingDrainLimit = U64(1024)


## Returns the Milk-V UART0 device descriptor.
proc consoleUart(): Uart16550 =
  Uart16550(base: MilkvUart0Base, regShift: U8(2), regWidth: U8(4))


## Returns a pointer to a Milk-V PLIC register.
proc plicReg(offset: U64): ptr U32 =
  cast[ptr U32](MilkvPlicBase + offset)


## Returns the PLIC enable register offset for an interrupt source.
proc plicEnableRegOffset(source: U32): U64 =
  PlicEnableOffset + MilkvPlicSModeContext * PlicEnableStride +
    U64(source div U32(32)) * U64(4)


## Returns the PLIC threshold register offset for the S-mode context.
proc plicThresholdRegOffset(): U64 =
  PlicContextOffset + MilkvPlicSModeContext * PlicContextStride +
    PlicThresholdOffset


## Writes the PLIC priority for an interrupt source.
proc setPlicPriority(source: U32, priority: U32) =
  volatileStore(plicReg(PlicPriorityOffset + U64(source) * U64(4)), priority)


## Enables a PLIC interrupt source for the S-mode context.
proc enablePlicSource(source: U32) =
  let offset = plicEnableRegOffset(source)
  let mask = U32(1) shl (source mod U32(32))
  let current = volatileLoad(plicReg(offset))
  volatileStore(plicReg(offset), current or mask)


## Sets the PLIC interrupt threshold for the S-mode context.
proc setPlicThreshold(threshold: U32) =
  volatileStore(plicReg(plicThresholdRegOffset()), threshold)


## Claims the next pending PLIC interrupt for the S-mode context.
proc claimPlic(): U32 =
  let offset = PlicContextOffset + MilkvPlicSModeContext * PlicContextStride +
    PlicClaimOffset
  volatileLoad(plicReg(offset))


## Completes a claimed PLIC interrupt for the S-mode context.
proc completePlic(source: U32) =
  let offset = PlicContextOffset + MilkvPlicSModeContext * PlicContextStride +
    PlicClaimOffset
  volatileStore(plicReg(offset), source)


## Clears stale UART RX and interrupt-identification state before IRQ enable.
proc clearStaleUartInterrupts(uart: Uart16550) =
  uartWrite(uart, UartIer, U32(0))
  discard uartRead(uart, UartIir)
  discard uartRead(uart, UartUsr)

  var spin = UartPendingDrainLimit
  while spin > U64(0) and (uartRead(uart, UartLsr) and UartLsrDataReady) != U32(0):
    discard uartRead(uart, UartRbr)
    dec spin

  discard uartRead(uart, UartIir)
  discard uartRead(uart, UartUsr)


## Acknowledges DW APB UART interrupt causes that are not RX FIFO data.
proc acknowledgeUartInterrupt*() =
  let uart = consoleUart()
  let iir = uartRead(uart, UartIir) and UartIirInterruptIdMask
  if iir == UartIirBusyDetect:
    discard uartRead(uart, UartUsr)


## Enables RX interrupts on the Milk-V DW APB UART.
proc enableUartRxInterrupt() =
  let uart = consoleUart()
  let lcr = uartRead(uart, UartLcr)
  uartWrite(uart, UartLcr, lcr and not UartLcrDlab)
  clearStaleUartInterrupts(uart)
  uartWrite(uart, UartFcr, UartFcrEnable or UartFcrClearRx or UartFcrClearTx)
  discard uartRead(uart, UartIir)
  uartWrite(uart, UartIer, UartIerRxAvailable)


## Initializes Milk-V external interrupt routing for runtime devices.
proc initExternalInterrupts*() =
  setPlicPriority(MilkvUart0Irq, U32(1))
  enablePlicSource(MilkvUart0Irq)
  setPlicThreshold(U32(0))
  enableUartRxInterrupt()
  arch.writeSie(arch.readSie() or SieSeie)


## Claims one external interrupt for the active S-mode context.
proc claimExternalInterrupt*(): U32 =
  claimPlic()


## Completes a claimed external interrupt for the active S-mode context.
proc completeExternalInterrupt*(source: U32) =
  if source != U32(0):
    completePlic(source)


## Returns whether a claimed source is the Milk-V UART0 RX interrupt.
proc isUartRxInterrupt*(source: U32): bool =
  source == MilkvUart0Irq
