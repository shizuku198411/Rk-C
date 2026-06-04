## Powers off Milk-V Duo 256M through the SG2002 RTC power controller.
import ../../arch/riscv64/arch
import ../../lib/types
import ./memory_layout
import volatile

const
  RtcCtrlUnlockKey = U64(0x04)
  RtcCtrl0 = U64(0x08)
  RtcSelect32kDomain = U64(0x03c)
  RtcShutdownRequest = U64(0x0c0)
  RtcUnlockValue = U32(0xab18)
  RtcPowerOffValue = U32(0xffff0801)
  RtcRequestValue = U32(1)
  RtcRequestTimeoutTicks = MilkvTimerFrequency
  RtcPowerOffWaitTicks = MilkvTimerFrequency


## Reads one 32-bit RTC power-controller register.
proc mmioRead(address: U64): U32 =
  volatileLoad(cast[ptr U32](address))


## Writes one 32-bit RTC power-controller register.
proc mmioWrite(address: U64, value: U32) =
  volatileStore(cast[ptr U32](address), value)
  arch.fenceIorwIorw()


## Waits until a register reaches the requested value or the timeout expires.
proc waitRegisterValue(address: U64, expected: U32, timeoutTicks: U64): bool =
  let start = arch.rdtime()
  while arch.rdtime() - start < timeoutTicks:
    if mmioRead(address) == expected:
      return true

  false


## Requests SoC poweroff using the same RTC sequence as the official Linux driver.
proc tryPowerOff*() =
  let rtcCtrlBase = MilkvRtcPowerBase
  let rtcBase = rtcCtrlBase + MilkvRtcRegisterOffset
  let shutdownRequestAddress = rtcBase + RtcShutdownRequest

  mmioWrite(rtcBase + RtcSelect32kDomain, RtcRequestValue)
  mmioWrite(rtcCtrlBase + RtcCtrlUnlockKey, RtcUnlockValue)
  mmioWrite(shutdownRequestAddress, RtcRequestValue)

  if not waitRegisterValue(shutdownRequestAddress, RtcRequestValue, RtcRequestTimeoutTicks):
    return

  mmioWrite(rtcCtrlBase + RtcCtrl0, RtcPowerOffValue)

  let start = arch.rdtime()
  while arch.rdtime() - start < RtcPowerOffWaitTicks:
    discard
