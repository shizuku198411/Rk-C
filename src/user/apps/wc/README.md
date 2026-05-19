# wc

`wc` counts lines, words, and bytes in a file.

## Usage

```text
wc <path>
wc --help
```

## Behavior

- Resolves the input path relative to the current working directory
- Reads the target file with `sysReadFile`
- Prints `<lines> <words> <bytes> <resolved-path>`
- Supports files up to the local 4096-byte buffer size

## RKX Metadata

- `stack_pages = 2`
- capabilities: none

## Notes

- Standard input mode is not supported yet
- The word count treats spaces, tabs, carriage returns, and newlines as separators
