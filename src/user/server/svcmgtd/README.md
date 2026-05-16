# svcmgtd

`svcmgtd` is the userspace service manager.
It is the first management server started after kernel boot and is responsible
for starting, registering, and monitoring the rest of the userspace services.

## Responsibilities

- Register itself as the service manager in the kernel
- Start managed services defined in `service_catalog`
- Register started services in the kernel service registry
- Receive service ready ACKs and move services to the running state
- Restart required services after stop or timeout
- Mark optional services as degraded after startup failure or ready timeout
- Handle control IPC, such as `svc restart <name>`

## Managed Services

Managed services are defined in `src/lib/service_catalog.nim` as
`managedServices`. Each entry contains a service kind, display name, executable
path, and required/optional flag.

In the current design, required services are restart targets until they become
available. Optional services are marked degraded on startup failure, process
exit, or ready timeout.

## Startup Flow

1. Get the current PID and print the startup log
2. Register as the service manager with `sysServiceManagerRegister()`
3. Copy `managedServices` into internal service state with `initServices()`
4. Start initial services in order
5. Wait for each service ready ACK or timeout
6. Enter the monitoring loop for control messages and service state

Initial startup uses `startInitialService`, so the next service is not started
until the current service has either sent a ready ACK or reached timeout.
This keeps shell startup behind the full service startup pass.

## Service State

- `srvStopped`
  - Not started or stopped
- `srvDegraded`
  - Optional service is unavailable
- `srvStarting`
  - Process has started and the manager is waiting for a ready ACK
- `srvRunning`
  - Ready ACK has been accepted

`readyDeadline` is set to `sysTicks() + ServiceReadyTimeoutTicks`.

## Ready ACK

Each server sends `SysIpcOpSvcReady` to `svcmgtd` after it finishes startup.
`svcmgtd` validates:

- The sender PID matches the managed service PID
- The service is currently in `srvStarting`
- Packet `arg0` matches the expected service kind

Only after those checks does `svcmgtd` call `sysServiceReady(kind, pid)` and
move the service to `srvRunning`. This avoids accepting ready spoofing from
unrelated processes.

## Control IPC

- `SysIpcOpSvcRestart`
  - Reads the service name from packet data
  - Finds the matching managed service
  - Calls `stopService` to unregister, kill, and wait
  - Calls `startService` to launch it again
- `SysIpcOpSvcReady`
  - Handles a ready ACK from a starting service

## Monitoring Loop

The main loop repeats:

- `pollControlMessages()`
  - Uses `sysIpcTryReceivePacket` to process control packets
- `monitorServices()`
  - Detects ready timeouts
  - Checks service liveness
  - Restarts required services
  - Marks optional services degraded
- `sysSleep(MonitorSleepTicks)`

Liveness checks use `sysPs` and treat zombie or unused process states as not
alive.

## Boundaries and Notes

- The process snapshot buffer is capped by `SysProcessMaxSlots`
- Ready timeout is controlled by `ServiceReadyTimeoutTicks`
- Optional services are not automatically retried after entering degraded state
- `startInitialService` currently starts `services[0]` through `services[3]`
  explicitly
- If the service catalog count or ordering changes, the initial startup code
  should be checked as well

## Related Files

- `svcmgtd.nim`: service manager implementation
- `src/lib/service_catalog.nim`: managed service list
- `src/user/server/lib/service_ready.nim`: ready ACK helper used by servers
- `src/lib/syscall_types.nim`: service kind, IPC op, and process state definitions
