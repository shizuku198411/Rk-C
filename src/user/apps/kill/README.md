# kill

`kill` asks the process management service to terminate a process.

## Usage

```text
kill <pid>
kill --help
```

## Behavior

- Parses the target PID from the command line
- Resolves the process service with service lookup helpers
- Sends `SysIpcOpProcKillRequest` to `procmgtd`
- Waits for `SysIpcOpProcKillResponse`
- Exits with status `1` when the request fails or the service reports failure

## RKX Metadata

- `stack_pages = 1`
- capabilities:
  - `sys_process_kill`

## Notes

- The request is sent through `procmgtd`; `procmgtd` checks the sender's effective capability
- The app does not call `sysKill` directly
