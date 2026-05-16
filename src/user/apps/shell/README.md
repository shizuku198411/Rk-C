# shell

`shell` is the interactive RK-C command shell.
It provides built-in commands, command execution, simple history, redirection,
and one-stage pipelines.

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
- `exit`
- `shutdown`

Other commands are executed from `/bin/<command>` with `sysExec`.

## Command Features

- Foreground command execution with `sysWait`
- Background execution with trailing `&`
- Output redirection with `>`
- One-stage pipe with `|`
- Basic stdin/stdout save and restore using `sysOpen`, `sysDup2`, and `sysClose`
- Prompt includes the current working directory from `sysGetCwd`

## Module Layout

- `shell.nim`
  - Main loop and built-in dispatch
- `command.nim`
  - Command parsing, exec, background jobs, redirection, and pipe handling
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
  - Shared shell state

## Boundaries and Notes

- Only one pipe is supported in a command line
- Redirection and pipe together are not currently supported
- Command paths are resolved as `/bin/<command>`
- Shell history has fixed in-memory and save-buffer limits
