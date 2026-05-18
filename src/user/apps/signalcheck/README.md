# signalcheck

`signalcheck` is a smoke-test app for the process signal/event notification
path.

## Usage

```text
signalcheck
```

## Behavior

- Starts a short-lived child process
- Waits for the child to exit
- Polls the pending process-signal queue
- Verifies that `child_exited` was delivered
- Verifies that the signal queue is empty afterward

## RKX Metadata

`rkx.toml`:

- `schema_version = 1`
- `stack_pages = 2`
- `capabilities = []`

No privileged capability is required.
