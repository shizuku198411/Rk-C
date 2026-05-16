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

## Notes

- Actual permission checks and kill policy are enforced by the kernel
- The app does not call `sysKill` directly
