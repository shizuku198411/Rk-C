# server/lib

`src/user/server/lib` contains small shared helpers used by userspace servers.
At the moment, it provides common logic for service registration waits and
service ready ACKs.

## Responsibilities

- Share startup logic that would otherwise be duplicated across servers
- Hide the small ready protocol between each server and `svcmgtd`
- Keep each server's `user_start` implementation focused on its own work

## `service_ready.nim`

### `waitUntilServiceRegistered(kind: U32): bool`

Waits until the current process PID is registered for the given service kind.

- Polls `registeredServicePidByKind(kind)` until it matches the current PID
- Uses `ServiceRegistrationWaitTicks` as the polling interval
- Uses `ServiceRegistrationTimeoutTicks` as the timeout
- Returns `false` on timeout

This is used by servers such as `blockd`, `fsd`, and `netd`, where `svcmgtd`
registers the service before the server announces readiness.

### `notifyServiceReady(kind: U32)`

Sends a `SysIpcOpSvcReady` packet to the service manager.

- Resolves `svcmgtd` with `servicePidByKind(SysServiceKindManager)`
- Stores the service kind in packet `arg0`
- Sends the packet with `sysIpcSendPacket`

`svcmgtd` verifies the sender PID and service kind before moving the service to
the running state.

## Users

- `blockd`
- `fsd`
- `netd`
- `procmgtd`

`procmgtd` currently sends the ready ACK but does not wait for service registry
registration in the same way as `blockd`, `fsd`, and `netd`.

## Related Files

- `service_ready.nim`: shared helper implementation
- `src/user/lib/ipc/service_client.nim`: service registry lookup helpers
- `src/lib/syscall_types.nim`: service kind and IPC op definitions
