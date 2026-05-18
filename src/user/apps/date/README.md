# date

`date` prints the current date and time reported by the kernel.

## Usage

```text
date
date --help
```

## Behavior

- Calls `sysGetDateTime`
- Prints the result as `YYYY/MM/DD HH:MM:SS`
- Exits with status `1` if the syscall fails or unexpected arguments are passed

## RKX Metadata

- `stack_pages = 1`
- capabilities: none

## Notes

- The displayed time depends on the kernel date/time source
- No formatting options are currently supported
