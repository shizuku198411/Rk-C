# Capability Model

Rk-C uses process capabilities to protect privileged kernel syscalls and to
avoid confused-deputy paths through user-space services.

Capabilities are intentionally split into two concepts:

- requested capabilities: what an RKX image asks for in its header
- effective capabilities: what the kernel actually grants to the process

An RKX image is not trusted to grant itself privileges. The RKX header is only a
request. The kernel intersects that request with its trusted policy when the
process is executed.

## Capability Definitions

The shared capability constants live in:

```text
src/lib/syscall_caps.nim
```

This file is the source of truth for both Nim code and the RKX packaging tool.
`scripts/make_rkx.py` parses it directly, so capability names are not duplicated
in Python.

| Bit | Name | Purpose |
| --- | --- | --- |
| 0 | `sys_service_manager` | Register the service manager and control service lifecycle operations. |
| 1 | `sys_raw_fs` | Use raw filesystem syscalls and filesystem-service operations. |
| 2 | `sys_raw_block` | Use raw block-device syscalls and block-service operations. |
| 3 | `sys_raw_net` | Use raw network-device syscalls. |
| 4 | `sys_process_list` | Read process metadata through process-list syscalls. |
| 5 | `sys_process_kill` | Request process termination through the kernel or process service. |
| 6 | `sys_trace_ctl` | Control syscall tracing. |
| 7 | `sys_shutdown` | Shut down the system. |

`SysCapAllKnown` is the mask of every capability bit currently understood by
the kernel. RKX images that request unknown bits are rejected by the loader.

## RKX Metadata

Each user app or server can request capabilities in its local RKX metadata file:

```toml
schema_version = 1
stack_pages = 2
capabilities = ["sys_process_kill"]
```

The metadata file is usually located at:

```text
src/user/apps/<name>/rkx.toml
src/user/server/<name>/rkx.toml
```

During packaging, `scripts/make_rkx.py`:

1. Reads `rkx.toml`.
2. Parses valid capability names from `src/lib/syscall_caps.nim`.
3. Rejects unknown capability names.
4. Encodes the requested capability mask into the RKX header.

This means the app directory declares what it needs, while the shared
capability definition still remains centralized.

## Load-Time Grant Policy

RKX loading happens in two phases:

1. `src/kernel/task/rkx_loader.nim` validates the image format.
2. `src/kernel/task/exec.nim` installs the image and grants capabilities.

The loader checks that:

- the RKX magic, version, and header size are valid
- segment ranges and alignment are valid
- the entry point is inside executable text
- stack page count is in range
- `capabilityMask` contains only known capability bits

After the image passes validation, `exec.nim` calculates the effective
capability mask:

```text
effective_caps = rkx_header.capabilityMask & trustedCapsForPath(path)
```

The trusted policy is currently path-based:

| Path | Trusted capabilities |
| --- | --- |
| `/bin/svcmgtd` | `sys_service_manager`, `sys_process_list`, `sys_process_kill` |
| `/bin/procmgtd` | `sys_process_list`, `sys_process_kill` |
| `/bin/procfsd` | `sys_process_list` |
| `/bin/fsd` | `sys_raw_fs` |
| `/bin/blockd` | `sys_raw_block` |
| `/bin/netd` | `sys_raw_net` |
| `/bin/stracectl` | `sys_trace_ctl` |
| `/bin/kill` | `sys_process_kill` |
| `/bin/shutdown` | `sys_shutdown` |
| `/bin/svc` | `sys_service_manager` |
| all other paths | none |

The process stores both masks:

- `requestedCapabilityMask`: copied from the RKX header
- `capabilityMask`: granted by the kernel policy

This keeps debugging clear: a process can request a capability and still receive
none if the kernel does not trust that executable path for that capability.

## Syscall Enforcement

The kernel syscall gate calls capability policy before dispatch:

```text
src/kernel/trap/syscall.nim
src/kernel/syscall/syscall_cap.nim
```

`handleSyscall()` calls `canSyscallByNumber()`. If the syscall is protected and
the current process is not allowed to use it, the kernel returns `-1` without
calling the subsystem handler.

`syscall_cap.nim` is the central policy file. It combines:

- the current process effective capability mask
- service identity checks from the kernel service registry
- target-specific checks, such as kill target restrictions

Protected syscall groups include:

- raw filesystem syscalls
- filesystem service receive/reply/register operations
- raw block syscalls
- block service receive/reply/register operations
- raw network syscalls
- process listing
- process kill
- service manager registration and service lifecycle mutation
- syscall trace control
- shutdown

Most normal user syscalls, such as regular file operations, IPC send/receive,
sleep, wait, exec, and pipe operations, are not capability-gated by this layer.
They are still protected by their own ABI, buffer, fd, and process lifecycle
checks.

## Service Identity

Some privileged paths require both a capability and a service role.

For example:

- raw filesystem access requires `sys_raw_fs` and the current process must be
  the registered filesystem service
- raw block access requires `sys_raw_block` and the current process must be the
  registered block service
- raw network access requires `sys_raw_net` and the current process must be the
  registered network service
- process listing requires `sys_process_list` and the current process must be
  the service manager, process service, or procfs service
- process kill requires `sys_process_kill` and the current process must be the
  service manager or process service

This prevents a normal app from gaining raw access just by editing its RKX
metadata. It also prevents a process with a raw capability from using it unless
it occupies the expected service role.

## IPC Capability Propagation

IPC packets include a capability mask field:

```text
src/lib/syscall_types.nim
```

User-space cannot forge this field. When a packet is sent, the kernel overwrites
the packet metadata:

```text
src/kernel/syscall/ipc/ipc_ops.nim
```

The kernel stamps:

- `senderPid`
- `capabilityMask` from the sender's effective process capabilities

Services can then authorize requests using the sender's effective capabilities.
This is used to reduce confused-deputy risk.

Current examples:

- `procmgtd` checks `sys_process_kill` before forwarding kill requests.
- `svcmgtd` checks `sys_service_manager` for service status, logs, start,
  stop, and restart commands.

The service must check packet capabilities for every privileged request that it
performs on behalf of another process.

## Observability

Runtime process capabilities are visible through procfs:

```text
/proc/<pid>/status
```

The status file shows both numeric masks and decoded names:

```text
requested_caps: 0x20 (sys_process_kill)
caps: 0x20 (sys_process_kill)
```

On-disk RKX headers can be inspected without executing the app:

```text
rkxinfo /bin/kill
rkxinfo kill
```

`rkxinfo` displays the RKX header capability mask. That value is the requested
mask only; it does not prove the kernel will grant it.

The current process can also query its own effective mask through `sysGetCap`.
The shell `getcap` test command and the `capcheck` app use this for smoke tests.

## Denial Behavior

Capability denial happens at two layers:

- kernel syscall denial: `handleSyscall()` returns `-1` before dispatch
- service request denial: the service returns an error response for unauthorized
  IPC requests

For example, a process without `sys_process_kill` cannot successfully ask
`procmgtd` to kill another process, because the service checks the kernel-stamped
sender capability mask.

## Adding a Capability

When adding a new capability:

1. Add the bit constant and name constant to `src/lib/syscall_caps.nim`.
2. Include the bit in `SysCapAllKnown`.
3. Add or update policy in `src/kernel/syscall/syscall_cap.nim`.
4. Add a trusted grant in `trustedCapsForPath()` if an executable should receive
   the capability.
5. Add the capability name to the relevant app or server `rkx.toml`.
6. Update user-facing capability formatters if needed.
7. Add tests for both grant and denial behavior.

Today, `procfsd` and `rkxinfo` each decode capability names for display. If
capability formatting grows further, moving that formatter into a shared
user/kernel-safe helper would reduce update points.

## Security Notes

The current grant policy is path-based. That is simple and works well with the
current appfs model, but it assumes the trusted executable paths cannot be
silently replaced by an attacker.

If `/bin` becomes writable, loaded from an untrusted disk, or updatable at
runtime, the grant model should move to a stronger root of trust, such as:

- a kernel-owned trusted manifest
- signed RKX images
- a read-only measured appfs image
- per-image hashes stored outside writable user data

Capabilities are also currently process-wide. They do not model per-object
rights such as "may kill only child processes" or "may access only this fd".
Those checks should be added at the relevant subsystem or service boundary when
needed.

There is no dynamic capability drop or inheritance model yet. `exec` creates a
new process capability set from the RKX request and kernel trusted policy.
