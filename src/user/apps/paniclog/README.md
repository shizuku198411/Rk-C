# paniclog

`paniclog` prints the user-mode panic log recorded by the kernel.

## Usage

```text
paniclog
paniclog --help
```

## Behavior

- Reads `/var/log/user_panic.log`
- Prints one line per recorded user fault
- Prints `no panic log` when the log file does not exist or is empty
- Each log line includes `pid`, `exe`, `scause`, `stval`, `sepc`, `sp`, and `a0` through `a3`

## RKX Metadata

- `stack_pages = 2`
- capabilities: none

## Notes

- The log is appended by the kernel when a user process faults
- Kernel faults still follow the kernel panic path and are not written here
