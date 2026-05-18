# IPC and Services

Rk-C uses IPC as the main boundary between applications and userland services.

## IPC Forms

There are two IPC styles:

- text messages
- structured packets

Structured packets are used for service protocols and request/reply style APIs.

## Service Registry

The kernel service registry tracks service PID, registration, and ready state.
Service kinds are shared through `src/lib/syscall_types.nim`.

`svcmgtd` owns service lifecycle policy:

- start managed services
- register services in the kernel
- accept ready ACKs
- restart required services
- mark optional services degraded
- expose status and recent logs

## Ready ACK

Servers send `SysIpcOpSvcReady` after startup. `svcmgtd` accepts it only when:

- sender PID matches the managed service PID
- the service is in `starting`
- packet `arg0` matches the expected service kind

This avoids ready spoofing from unrelated processes.

## Supervision

`svcmgtd` tracks:

- service state
- PID
- start count
- restart count
- last ready tick
- last exit status
- last failure reason
- recent supervision event logs

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

Control operations require `sys_service_manager` capability. Required services
cannot be stopped through `svc stop`.

## Raw Access Boundary

Raw filesystem, block, network, and process operations are restricted to trusted
services by syscall capability policy. Normal applications should use service
protocols instead of raw syscalls.

