# rm

`rm` removes one or more files.

## Usage

```text
rm <path> [path...]
rm --help
```

## Behavior

- Parses one or more path arguments
- Rejects paths that do not fit the local path buffer
- Calls `sysUnlink` for each path
- Stops at the first failure and exits with status `1`

## RKX Metadata

- `stack_pages = 1`
- capabilities: none

## Notes

- Directory removal is handled by `rmdir`
- Path resolution is handled by the kernel filesystem syscall layer
