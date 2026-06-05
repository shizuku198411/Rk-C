## Provides QEMU virt interrupt controller and UART RX interrupt setup.
import ../../arch/riscv64/arch
import ../../lib/types
import ./memory_layout
import volatile


const
  QemuUart0Irq = U32(10)
  QemuPlicSModeContext = U64(1)
  PlicPriorityOffset = U64(0x000000)
  PlicEnableOffset = U64(0x002000)
  PlicEnableStride = U64(0x80)
  PlicContextOffset = U64(0x200000)
  PlicContextStride = U64(0x1000)
  PlicThresholdOffset = U64(0x0)
  PlicClaimOffset = U64(0x4)
  UartIer = U64(1)
  UartFcr = U64(2)
  UartIerRxAvailable = U8(1 shl 0)
  UartFcrEnable = U8(1 shl 0)
  UartFcrClearRx = U8(1 shl 1)
  UartFcrClearTx = U8(1 shl 2)


## Returns a pointer to a QEMU PLIC register.
proc plicReg(offset: U64): ptr U32 =
  cast[ptr U32](QemuPlicBase + offset)


## Returns a pointer to a QEMU UART register.
proc uartReg(reg: U64): ptr U8 =
  cast[ptr U8](QemuUart0Base + reg)


## Writes the PLIC priority for an interrupt source.
proc setPlicPriority(source: U32, priority: U32) =
  volatileStore(plicReg(PlicPriorityOffset + U64(source) * U64(4)), priority)


## Enables a PLIC interrupt source for the S-mode context.
proc enablePlicSource(source: U32) =
  let offset = PlicEnableOffset + QemuPlicSModeContext * PlicEnableStride +
    U64(source div U32(32)) * U64(4)
  let mask = U32(1) shl (source mod U32(32))
  let current = volatileLoad(plicReg(offset))
  volatileStore(plicReg(offset), current or mask)


## Sets the PLIC interrupt threshold for the S-mode context.
proc setPlicThreshold(threshold: U32) =
  let offset = PlicContextOffset + QemuPlicSModeContext * PlicContextStride +
    PlicThresholdOffset
  volatileStore(plicReg(offset), threshold)


## Claims the next pending PLIC interrupt for the S-mode context.
proc claimPlic(): U32 =
  let offset = PlicContextOffset + QemuPlicSModeContext * PlicContextStride +
    PlicClaimOffset
  volatileLoad(plicReg(offset))


## Completes a claimed PLIC interrupt for the S-mode context.
proc completePlic(source: U32) =
  let offset = PlicContextOffset + QemuPlicSModeContext * PlicContextStride +
    PlicClaimOffset
  volatileStore(plicReg(offset), source)


## Enables RX interrupts on the QEMU 16550 UART.
proc enableUartRxInterrupt() =
  volatileStore(uartReg(UartFcr), UartFcrEnable or UartFcrClearRx or UartFcrClearTx)
  volatileStore(uartReg(UartIer), UartIerRxAvailable)


## Initializes QEMU external interrupt routing for runtime devices.
proc initExternalInterrupts*() =
  setPlicPriority(QemuUart0Irq, U32(1))
  enablePlicSource(QemuUart0Irq)
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


## Acknowledges QEMU UART interrupt causes after RX drain.
proc acknowledgeUartInterrupt*() =
  discard


## Returns whether a claimed source is the QEMU UART RX interrupt.
proc isUartRxInterrupt*(source: U32): bool =
  source == QemuUart0Irq
