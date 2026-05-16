# ls

`ls` lists directory entries.

## Usage

```text
ls [-l] [path]
ls --help
```

## Behavior

- Uses the current directory when no path is provided
- Calls `sysLs` into a fixed directory entry array
- Prints names in compact form by default
- Prints one entry per line with size information when `-l` is used
- Appends `/` to directory names

## Boundaries and Notes

- The maximum number of entries is fixed by the local `LsMaxEntries` buffer
- Unknown options or too many arguments are rejected
