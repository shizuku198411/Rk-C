# id

`id` prints the current process filesystem identity.

## Usage

```text
id
id --help
```

## Behavior

- Calls `sysGetUid` and `sysGetGid`
- Prints the current UID and GID as decimal values
- In the initial root-only user model, both values are `0`

## RKX Metadata

- `stack_pages = 1`
- capabilities: none

## Boundaries and Notes

- UID/GID are filesystem identities only
- They do not affect RKX capabilities or privileged syscall checks
