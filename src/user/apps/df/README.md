# df

`df` prints the current filesystem capacity summary.

## Usage

```text
df
df --help
```

## Behavior

- Reads `/proc/fsinfo`
- Prints rootfs, tmpfs, and appfs capacity in a df-like table
- Shows block usage in 1 KiB units and file slot usage per filesystem

## RKX Metadata

- `stack_pages = 1`
- capabilities: none

## Notes

- The command is read-only
- `/bin` is reported as the read-only appfs image
