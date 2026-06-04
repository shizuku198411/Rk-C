## Coordinates orderly filesystem, device, indicator, and platform shutdown.
import ../dev/console
import ../fs/blockdev
import ../fs/fs
import ../../platform/shutdown as platform_shutdown
import ../../platform/status_led


## Prepares persistent state and powers off through the active platform backend.
proc shutdownSystem*(): int =
  print("[shutdown] begin\n")
  fsBeginShutdown()

  if fsFlushMetadata() < 0:
    print("[shutdown] flush filesystem metadata ... FAIL\n")
    fsCancelShutdown()
    return -1
  print("[shutdown] flush filesystem metadata ... OK\n")

  if blockSync() < 0:
    print("[shutdown] sync block device ... FAIL\n")
    fsCancelShutdown()
    return -1
  print("[shutdown] sync block device ... OK\n")

  if not status_led.setStatusLed(false):
    print("[shutdown] turn off status LED ... FAIL\n")
  else:
    print("[shutdown] turn off status LED ... OK\n")

  print("[shutdown] platform power off ...\n")
  platform_shutdown.powerOff()
