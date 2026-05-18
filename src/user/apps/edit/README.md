# edit

`edit` is a tiny terminal file editor for the RK-C userspace environment.

## Usage

```text
edit <path>
edit --help
```

## Controls

- Arrow keys move the cursor
- `C-x C-s` saves the buffer
- `C-x C-c` exits

## Behavior

- Loads the target file with `sysReadFile`
- Edits the file in a fixed in-memory buffer
- Saves the full buffer contents with `sysWriteFile`
- Uses ANSI escape sequences for screen and cursor updates

## RKX Metadata

- `stack_pages = 8`
- capabilities: none

## Boundaries and Notes

- The edit buffer is fixed size
- Long paths are rejected before opening the file
- This is a simple single-file editor; it does not implement advanced terminal
  editing features
