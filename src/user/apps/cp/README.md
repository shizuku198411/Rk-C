# cp

`cp` copies one file to another path.

## Usage

```text
cp <srcpath> <dstpath>
cp --help
```

## Behavior

- Resolves source and destination paths into separate buffers
- Reads the entire source file with `sysReadFile`
- Writes the copied bytes with `sysWriteFile`
- Fails if the source cannot be read, the destination cannot be written, or the file is larger than the local 4096-byte buffer

## RKX Metadata

- `stack_pages = 2`
- capabilities: none

## Notes

- Directory copy is not supported
- Writes under immutable paths such as `/bin` are rejected by the filesystem layer
