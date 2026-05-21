# login

`login` authenticates a user and starts an interactive shell for that user.

## Usage

```text
login
login --help
```

## Behavior

- Prompts for a username and password on the console
- Sends authentication requests through the shared user database client
- Starts `/bin/shell` after successful authentication
- Uses `sysExecAs` so the `login` process stays root while only the child shell
  runs with the authenticated user's UID and GID
- Waits for the shell to exit, then returns to the login prompt
- Does not echo password input

## Authentication

Authentication is handled by `userd`.

- Public account data comes from `/etc/passwd`
- Password hashes come from `/etc/shadow`
- The password itself is sent to `userd` over IPC for verification

## RKX Metadata

- stack_pages = 2
- capabilities: none
- allowed users: all

`login` does not request a capability itself. The privileged part of launching a
shell as another UID is enforced by the kernel-side `sysExecAs` check, which is
root-only.

## Boundaries and Notes

- The input line buffer is fixed size
- Failed login attempts print a generic error
- `login` is intended to be started by the initial boot flow, not as a regular
  replacement for `su`
- `su` changes the current shell identity, while `login` starts a new shell
  session and keeps the login supervisor alive
