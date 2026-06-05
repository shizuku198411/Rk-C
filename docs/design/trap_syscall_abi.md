# Trap and Syscall ABI

Rk-C uses RISC-V traps for syscalls, timer interrupts, external interrupts, and fault handling.

## Trap Entry

The assembly trap entry saves registers into a trap frame, enters Nim trap handling, and restores the interrupted context before `sret`.

```text
U-mode or S-mode event
  -> src/arch/riscv64/trap.S
  -> TrapFrame
  -> src/kernel/trap/trap.nim
  -> syscall / interrupt / fault handler
  -> restore frame
  -> sret or schedule
```

Timer interrupts drive preemption. External interrupts feed platform devices such as Milk-V UART RX. User faults terminate the current user process, while kernel faults panic.

## Syscall ABI

Shared syscall numbers live in:

```text
src/lib/syscall_ids.nim
```

Shared syscall structures live in:

```text
src/lib/syscall_types.nim
```

The userland raw syscall entry point is:

```text
src/user/lib/syscall/base.nim
src/user/lib/syscall.S
```

Domain-specific wrappers live in:

```text
src/user/lib/syscall/fs.nim
src/user/lib/syscall/ipc.nim
src/user/lib/syscall/net.nim
src/user/lib/syscall/process.nim
src/user/lib/syscall/service.nim
src/user/lib/syscall/system.nim
src/user/lib/syscall/trace.nim
```

`src/user/lib/core/syscall.nim` re-exports those wrappers so existing apps can import one stable module.

## Register Convention

The user wrapper places syscall arguments in the normal argument registers and places the syscall number in `a3`.

```text
a0 = arg0 / return value
a1 = arg1
a2 = arg2
a3 = syscall number
ecall
```

The kernel dispatches through `src/kernel/trap/syscall.nim`.

## Dispatch Layout

Subsystem implementations live under `src/kernel/syscall/`.

```text
src/kernel/syscall/
  blk/
  fs/
  io/
  ipc/
  mm/
  net/
  service/
  system/
  task/
```

The dispatcher should remain thin: it maps syscall numbers to subsystem handlers, applies capability checks, updates `lastError`, and emits syscall trace records.

## Error Reporting

Most failing syscalls return `-1` and set `lastError`. Error constants are shared in `src/lib/syscall_types.nim`.

Examples:

- `SysErrPerm`
- `SysErrNoEnt`
- `SysErrAccess`
- `SysErrNotDir`
- `SysErrIsDir`
- `SysErrInval`
- `SysErrCap`

Apps should prefer domain wrappers and userland helpers rather than hard-coding raw negative values.

## Syscall Trace

Syscall tracing is controlled through `stracectl`.

Supported modes include:

- global trace on/off
- trace one PID
- trace only a child command, then turn tracing off when it exits

Trace formatting names syscalls, decodes selected arguments, prints return values, and truncates large write buffers to keep logs readable.

## External Interrupts

External interrupts are platform-dispatched.

```text
trap.nim
  -> platform/interrupt_backend.claimExternalInterrupt()
  -> ttyPollInput(Tty0Id) when UART source
  -> wake TTY readers
  -> platform-specific UART ack
  -> platform/interrupt_backend.completeExternalInterrupt()
```

QEMU and Milk-V differ here: Milk-V uses PLIC source claim/complete for UART0 RX, while QEMU keeps the backend minimal.

## Capability Gate

Before dispatch, `handleSyscall()` calls `canSyscallByNumber()` from `src/kernel/syscall/syscall_cap.nim`.

Protected syscall groups include:

- raw filesystem
- raw block
- raw network
- service mutation
- process list and kill
- trace control
- shutdown

See [Capability Model](capabilities.md) for the full grant and enforcement flow.
