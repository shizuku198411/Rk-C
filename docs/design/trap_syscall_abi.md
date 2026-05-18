# Trap and Syscall ABI

Rk-C uses RISC-V traps for syscalls, timer interrupts, and fault handling.

## Trap Entry

The trap entry path saves register state into a trap frame, dispatches to kernel
handlers, and restores state before returning to the interrupted context.

Timer interrupts are used for preemptive scheduling. User faults are reported
and kill the current user process. Kernel faults panic.

## Syscall ABI

Shared syscall identifiers live in:

```text
src/lib/syscall_ids.nim
```

Shared ABI types live in:

```text
src/lib/syscall_types.nim
```

User wrappers live in:

```text
src/user/lib/core/syscall.nim
```

Kernel dispatch lives in:

```text
src/kernel/trap/syscall.nim
```

Subsystem implementations live under:

```text
src/kernel/syscall/
```

## Capability Checks

Syscall capability policy is centralized in:

```text
src/kernel/syscall/syscall_cap.nim
```

RKX headers can request capabilities, but the kernel grants only capabilities
allowed by its trusted policy. This prevents a modified app image from granting
itself arbitrary raw access.

Actual capability masks can be inspected with:

```text
/proc/<pid>/status
```

The detailed request, grant, IPC propagation, and service authorization model is
documented in [Capability Model](capabilities.md).
