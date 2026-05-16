# ipc

`ipc` is a small manual IPC test utility.

## Usage

```text
ipc send <pid> <message>
ipc receive
ipc --help
```

## Behavior

- `send` sends a text message to a target PID with `sysIpcSend`
- `receive` waits for one message with `sysIpcReceive`
- Received messages are printed as `from <pid>: <message>`

## Boundaries and Notes

- The message is copied into the kernel IPC message buffer
- Message size is limited by the syscall IPC ABI
- `receive` is blocking
