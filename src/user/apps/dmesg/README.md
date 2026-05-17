# dmesg

`dmesg` prints the recent kernel log ring buffer.

## Usage

```text
dmesg
dmesg --help
```

## Behavior

- Reads the kernel log through the `SysKmsg` syscall
- Prints the newest retained log bytes in chronological order
- The kernel keeps a fixed-size ring buffer, so older messages are dropped once
  the buffer wraps

## Related Files

- Kernel log storage: `src/kernel/dev/klog.nim`
- Kernel console integration: `src/kernel/dev/console.nim`
- `/proc/kmsg` view: `src/user/server/procfsd/procfsd.nim`
