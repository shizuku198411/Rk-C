# stracectl

`stracectl` controls syscall tracing from userspace.

## Usage

```text
stracectl on
stracectl off
stracectl [-v] <pid>
stracectl [-v] <command> [args...]
stracectl --help
```

## Behavior

- `on` enables global tracing
- `off` disables tracing
- `<pid>` enables tracing for an existing process
- `<command> [args...]` executes `/bin/<command>`, traces it, waits for it, and
  returns the child status
- `-v` enables verbose syscall details

## RKX Metadata

- `stack_pages = 2`
- capabilities:
  - `sys_trace_ctl`

## Notes

- Uses `sysTraceCtl`
- When tracing a command, the app resets verbose and trace state after `sysWait`
- Command paths are resolved under `/bin`
