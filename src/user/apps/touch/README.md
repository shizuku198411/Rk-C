# touch

`touch` creates empty files.

## Usage

```text
touch <path>
touch --help
```

## Behavior

- Parses one or more path arguments
- Resolves each path relative to the current working directory
- Creates each target by issuing a zero-byte `sysWriteFile`
- Stops at the first failure and exits with status `1`

## RKX Metadata

- `stack_pages = 1`
- capabilities: none

## Notes

- This implementation does not update timestamps
- Writes under immutable paths such as `/bin` are rejected by the filesystem layer
