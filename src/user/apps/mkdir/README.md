# mkdir

`mkdir` creates one or more directories.

## Usage

```text
mkdir <path> [path...]
mkdir --help
```

## Behavior

- Parses one or more path arguments
- Rejects paths that do not fit the local path buffer
- Calls `sysMkdir` for each path
- Stops at the first failure and exits with status `1`

## Notes

- Parent directory creation is not recursive
- Path resolution is handled by the kernel filesystem syscall layer
