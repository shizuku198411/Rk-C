## Controls the active-high onboard blue status LED on Milk-V Duo 256M.
import ../../arch/riscv64/arch
import ../../lib/types
import ./memory_layout
import volatile

const
  GpioSwPortData = U64(0x00)
  GpioSwPortDirection = U64(0x04)
  PinmuxFunctionMask = U32(0x7)
  StatusLedGpioFunction = U32(0)


## Reads one 32-bit MMIO register.
proc mmioRead(address: U64): U32 =
  volatileLoad(cast[ptr U32](address))


## Writes one 32-bit MMIO register.
proc mmioWrite(address: U64, value: U32) =
  volatileStore(cast[ptr U32](address), value)
  arch.fenceIorwIorw()


## Sets the active-high onboard blue status LED state.
proc setStatusLed*(on: bool): bool =
  let mask = U32(1) shl MilkvStatusLedPin
  let pinmuxAddress = MilkvPinmuxBase + MilkvStatusLedPinmuxOffset
  let dataAddress = MilkvGpioEBase + GpioSwPortData
  let directionAddress = MilkvGpioEBase + GpioSwPortDirection

  let pinmux = mmioRead(pinmuxAddress)
  mmioWrite(pinmuxAddress, (pinmux and not PinmuxFunctionMask) or StatusLedGpioFunction)

  mmioWrite(directionAddress, mmioRead(directionAddress) or mask)

  let current = mmioRead(dataAddress)
  if on:
    mmioWrite(dataAddress, current or mask)
  else:
    mmioWrite(dataAddress, current and not mask)

  let pinmuxReady = (mmioRead(pinmuxAddress) and PinmuxFunctionMask) == StatusLedGpioFunction
  let directionReady = (mmioRead(directionAddress) and mask) != U32(0)
  let outputHigh = (mmioRead(dataAddress) and mask) != U32(0)
  pinmuxReady and directionReady and outputHigh == on
