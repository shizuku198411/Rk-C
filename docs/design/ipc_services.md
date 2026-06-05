# IPC and Services

Rk-C uses IPC as the primary boundary between normal applications and privileged userland services. The kernel provides queues, packet stamping, service registration, and capability enforcement. Userspace services own policy and higher-level protocols.

## IPC Forms

There are two IPC forms:

- text messages for simple experiments and the `ipc` command
- structured packets for service protocols and request/reply APIs

Structured packets use `SysIpcPacket` from `src/lib/syscall_types.nim`.

The kernel stamps packet metadata on send:

- sender PID
- sender UID
- sender GID
- sender effective capability mask

Userland cannot forge these fields.

## Request/Reply Pattern

Service clients normally use a request/reply helper path:

```text
client app
  -> find service PID through service list
  -> ipc_send_packet(request)
  -> ipc_receive_packet(reply)
  -> validate reply op/id/result
```

Common request/reply helpers exist for userland and kernel-mediated service operations. New service protocols should reuse these helpers instead of hand-writing packet loops in every app.

## Service Registry

The kernel service registry tracks:

- service kind
- registered PID
- registered state
- ready state
- availability

Service kinds are defined in `src/lib/syscall_types.nim`.

Known managed services:

| Kind | Name | Required | Purpose |
| --- | --- | --- | --- |
| `SysServiceKindProcess` | `procmgtd` | yes | Process list and kill mediation |
| `SysServiceKindBlock` | `blockd` | yes | Raw block-device access |
| `SysServiceKindFs` | `fsd` | yes | Filesystem operations |
| `SysServiceKindUser` | `userd` | yes | User/group/auth database |
| `SysServiceKindProcFs` | `procfsd` | no | `/proc` virtual files |
| `SysServiceKindNet` | `netd` | no | Network stack |

`svcmgtd` is the service manager and registers as `SysServiceKindManager`.

## svcmgtd

`svcmgtd` owns lifecycle policy:

- start managed services
- pass platform policy arguments such as `--no-network`
- accept `SysIpcOpSvcReady`
- restart required services
- mark optional services degraded
- expose service status and recent logs
- mediate `svc` command operations

Ready ACK validation requires:

- sender PID matches the expected service PID
- the service is in the expected startup state
- packet `arg0` matches the expected service kind

This avoids ready spoofing by unrelated processes.

## Service Fallback Policy

Early boot sometimes needs filesystem or block access before the service is registered. The kernel permits raw fallback only while the target service is not registered.

```text
service not registered
  -> raw fallback allowed for bootstrap

service registered
  -> raw fallback closed
  -> requests must go through the service boundary
```

This prevents a dead registered service from silently bypassing the microkernel boundary.

## Service Commands

The `svc` command exposes:

```text
svc list
svc status [service]
svc degraded
svc logs
svc start <service>
svc stop <service>
svc restart <service>
```

Lifecycle mutation requires `sys_service_manager` capability. Required services are protected from normal stop operations.

## procmgtd

`procmgtd` centralizes process management requests that used to be direct command syscalls:

- `ps` requests process information through procmgtd
- `kill` requests process termination through procmgtd

The kernel still owns the actual process table and kill enforcement. procmgtd is the userland policy/API layer.

## userd

`userd` owns:

- `/etc/passwd`
- `/etc/shadow`
- `/etc/group`
- username and UID resolution
- group name and GID resolution
- password authentication
- password update requests

Default users are created when databases are absent:

```text
root:0:0:/
rkc:1000:1000:/home/rkc
```

Passwords are stored in `/etc/shadow` using PBKDF2-SHA256 records, not plaintext `/etc/passwd`.

## Raw Access Boundary

Raw filesystem, raw block, raw network, process-list, kill, trace, and shutdown operations are capability-gated. Services must also occupy the expected service role.

For example:

- `fsd` needs `sys_raw_fs` and must be registered as filesystem service.
- `blockd` needs `sys_raw_block` and must be registered as block service.
- `netd` needs `sys_raw_net` and must be registered as network service.

This avoids both RKX header forgery and confused-deputy paths through trusted services.
