# ps

`ps` lists processes through the process management service.

## Usage

```text
ps
ps --help
```

## Behavior

- Sends `SysIpcOpProcListRequest` to `procmgtd`
- Receives the process count response
- Receives one process entry packet per process
- Prints PID, parent PID, process state, mode, and executable path

## Boundaries and Notes

- The local process entry buffer is fixed size
- Process information is transported as `SysProcessInfo` through IPC packet data
- The app uses `procmgtd` instead of calling `sysPs` directly
