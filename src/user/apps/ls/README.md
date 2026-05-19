# ls

`ls` lists directory entries.

## Usage

```text
ls [-a] [-l] [path]
ls --help
```

## Behavior

- Uses the current directory when no path is provided
- Calls `sysLs` into a fixed directory entry array
- Prints names in compact form by default
- Hides entries beginning with `.` by default
- Shows hidden entries, including `.` and `..`, when `-a` is used
- Prints one entry per line with size information when `-l` is used
- Appends `/` to directory names
- Uses the shared option parser for short options and `--help`

## RKX Metadata

- `stack_pages = 2`
- capabilities: none

## Boundaries and Notes

- The maximum number of entries is fixed by the local `LsMaxEntries` buffer
- Unknown options or too many arguments are rejected
