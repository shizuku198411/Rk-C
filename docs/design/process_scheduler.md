# Process, Scheduler, and Lifecycle

The process table is fixed-size and currently sized by `SysProcessMaxSlots`.

## Process States

Processes move through:

```text
unused
runnable
running
sleeping
zombie
```

The kernel tracks PID, PPID, mode, executable path, user image metadata, CPU
ticks, memory pages, file descriptors, cwd, and capability masks.

## Scheduling

Timer interrupts drive preemption for user processes. A timer interrupt requests
rescheduling, and user-mode return paths can yield when needed.

The scheduler also supports explicit yield and sleeping.

## Lifecycle

Important lifecycle paths:

- `exec` creates a user process from an RKX image
- `exit` marks a process zombie
- `wait` reaps a child zombie and releases resources
- detached processes are auto-reaped
- process discard releases address space, kernel stack, fd table, pipes, and
  pending process metadata

If no process slot is available, user-visible exec paths report failure instead
of silently hanging.

## Observability

Process information is available through:

- `ps`
- `ps -f`
- `ps -l`
- `ps -e`
- `/proc/processes`
- `/proc/<pid>/status`
- `/proc/<pid>/rkx_map`

