## Dispatches external interrupt setup and handling to the active platform.
import ../lib/types

when defined(platformMilkVDuo256m):
  import ./milkv_duo256m/interrupt_backend as backend
else:
  import ./qemu_virt/interrupt_backend as backend


## Initializes external interrupt routing for runtime devices.
proc initExternalInterrupts*() =
  backend.initExternalInterrupts()


## Claims one external interrupt on the active platform.
proc claimExternalInterrupt*(): U32 =
  backend.claimExternalInterrupt()


## Completes a claimed external interrupt on the active platform.
proc completeExternalInterrupt*(source: U32) =
  backend.completeExternalInterrupt(source)


## Acknowledges platform UART interrupt causes after RX drain.
proc acknowledgeUartInterrupt*() =
  backend.acknowledgeUartInterrupt()


## Returns whether a claimed source is a UART RX interrupt.
proc isUartRxInterrupt*(source: U32): bool =
  backend.isUartRxInterrupt(source)
