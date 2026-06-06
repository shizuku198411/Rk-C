# cpuinfo

`cpuinfo` prints the CPU platform summary and scheduler runtime accounting exposed by procfs.

## Usage

```text
cpuinfo
cpuinfo --help
```

## Behavior

- Reads `/proc/cpuinfo`
- Prints static platform fields such as platform, SoC, ISA, MMU, hart count, and timebase
- Prints runtime accounting fields such as total ticks, idle ticks, busy ticks, and usage

## RKX Metadata

- `stack_pages = 1`
- capabilities: none

## Notes

- The command is read-only
- The displayed static CPU fields come from the boot-time CPU info snapshot managed by the kernel
