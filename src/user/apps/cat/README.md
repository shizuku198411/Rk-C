# cat

`cat` prints file contents or copies standard input to standard output.

## Usage

```text
cat [path]
cat --help
```

## Behavior

- With no path, reads from fd `0` until EOF and writes to fd `1`
- With one path, reads the file with `sysReadFile` and writes the contents
- Appends a newline after file output when the file does not already end with one
- Uses a fixed `CatBufferSize = 4096` buffer

## Notes

- Only one file path is supported
- Long paths are rejected before calling the syscall
- Read failures exit with status `1`
