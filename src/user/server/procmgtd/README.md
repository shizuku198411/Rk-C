# procmgtd

`procmgtd` is the userspace process management server.
It handles IPC requests from tools such as `ps` and `kill`, then calls the
kernel process syscalls and returns the result to the requester.

## Responsibilities

- Receive process list requests and return `sysPs` results over IPC
- Receive process kill requests and call `sysKill`
- Keep process management apps less tightly coupled to raw kernel syscall usage
- Notify `svcmgtd` with a service ready ACK after startup

## Startup Flow

1. `svcmgtd` starts `/bin/procmgtd`
2. `notifyServiceReady(SysServiceKindProcess)` sends a ready ACK to `svcmgtd`
3. `sysIpcReceivePacket` waits for process management requests in a loop

Unlike `blockd`, `fsd`, and `netd`, the current `procmgtd` implementation does
not poll until it sees itself registered in the service registry.

## IPC Requests

- `SysIpcOpProcListRequest`
  - Uses `arg0` as the requested maximum entry count
  - Clamps values less than or equal to zero, or values above `ProcessCap`, to `ProcessCap`
  - Calls `sysPs` to collect process information
  - Sends `SysIpcOpProcListResponse` with the total count
  - Sends one `SysIpcOpProcListEntry` packet per process entry
- `SysIpcOpProcKillRequest`
  - Uses `arg0` as the target PID
  - Calls `sysKill`
  - Sends `SysIpcOpProcKillResponse` with the result

Process entries are copied into IPC packet data with `copyToPacketData`.

## Boundaries and Notes

- The local process list buffer is capped by `ProcessCap = 16`
- `SysProcessInfo` is copied directly into IPC packet data, so ABI changes must
  stay in sync with clients
- Permission checks and kill policy are delegated to the kernel
- Unknown IPC ops are currently ignored

## Related Files

- `procmgtd.nim`: server implementation
- `../lib/service_ready.nim`: shared ready ACK helper
- `src/user/lib/ipc/packet_data.nim`: IPC packet data copy helper
- `src/lib/syscall_types.nim`: `SysProcessInfo` and IPC op definitions
