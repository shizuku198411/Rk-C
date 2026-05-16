# rmdir

`rmdir` removes one or more directories.

## Usage

```text
rmdir <path> [path...]
rmdir --help
```

## Behavior

- Parses one or more path arguments
- Rejects paths that do not fit the local path buffer
- Calls `sysRmdir` for each path
- Stops at the first failure and exits with status `1`

## Notes

- File removal is handled by `rm`
- Recursive directory removal is not implemented
