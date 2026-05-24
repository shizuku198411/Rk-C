# shell

`shell` is the interactive RK-C command shell.
It provides built-in commands, command execution, simple history, redirection,
and one-stage pipelines.
Its mutable command and history buffers are backed by one Nim ORC-managed arena.
The userland ORC build uses a small configurable initial allocator arena suitable
for a resident shell process.

## Startup

- Runs as the default interactive user process after service startup
- Prints the banner from `user_start`
- Loads command history from `/.history`
- Repeatedly prints the prompt, reads one line, and dispatches the command

## Built-ins

- `help`
- `cd`
- `ticks`
- `traps`
- `bitmap`
- `history`
- `which`
- `exit`
- `shutdown`

Other commands are resolved using the shared executable search policy and executed
with `sysExec`.

## Command Features

- Foreground command execution with `sysWait`
- Background execution with trailing `&`
- Output redirection with `>`
- One-stage pipe with `|`
- Basic stdin/stdout save and restore using `sysOpen`, `sysDup2`, and `sysClose`
- Prompt includes the current working directory from `sysGetCwd`
- Command lookup order is explicit paths, `/home/<user>/bin`, `/usr/bin`, then `/bin`

## RKX Metadata

- `stack_pages = 4`
- capabilities:
  - `sys_shutdown`

## Module Layout

- `shell.nim`
  - Main loop and built-in dispatch
- `command.nim`
  - Command parsing, resolver use, exec, background jobs, redirection, and pipe handling
- `builtins.nim`
  - Built-in command implementations
- `help.nim`
  - Help text
- `history.nim`
  - In-memory history and `/.history` persistence
- `line_editor.nim`
  - Interactive line input and cursor editing
- `prompt.nim`
  - Prompt rendering
- `state.nim`
  - Shared shell state and the ORC-managed buffer arena

## Boundaries and Notes

- Only one pipe is supported in a command line
- Redirection and pipe together are not currently supported
- Explicit slash-containing command paths do not fall back to the search path
- Shell history has fixed in-memory and save-buffer limits
