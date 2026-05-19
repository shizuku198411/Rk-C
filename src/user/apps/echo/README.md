# echo

`echo` writes its arguments to standard output.

## Usage

```text
echo "<str1 [str2...]>"
echo --help
```

## Behavior

- Parses one or more arguments
- Writes arguments separated by a single space
- Appends a trailing newline
- Exits with status `1` when no arguments are provided

## RKX Metadata

- `stack_pages = 1`
- capabilities: none

## Notes

- Shell redirection can be used to write the output into a file
- Quoted arguments are parsed by the shared user argument parser
