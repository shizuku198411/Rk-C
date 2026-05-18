# ps

`ps` lists processes through the process management service.

## Usage

```text
ps [-f] [-e] [-l]
ps --help
```

## Behavior

- Sends `SysIpcOpProcListRequest` to `procmgtd`
- Receives the process count response
- Receives one process entry packet per process
- Without options, prints PID and executable path for the parent shell and
  processes spawned from that shell
- `-f` prints PID, parent PID, process state, mode, and executable path
- `-e` lists every active process instead of only the parent shell subtree
- `-l` adds CPU percentage and memory page count columns
- `-f` and `-e` can be combined, for example `ps -ef`
- Split options also work, for example `ps -e -f`

## RKX Metadata

- `stack_pages = 2`
- capabilities: none
- Process data is accessed through `procmgtd`; this app does not request `sys_process_list`

## Boundaries and Notes

- The local process entry buffer is fixed size
- Process information is transported as `SysProcessInfo` through IPC packet data
- The app uses `procmgtd` instead of calling `sysPs` directly
