# procfsd

`procfsd` is the userspace procfs server.

It provides `/proc`-style virtual files through IPC behind `fsd`, so normal file
commands can inspect kernel and process state with paths such as
`/proc/processes` and `/proc/<pid>/status`.

## Responsibilities

- Serve `/proc` directory listings
- Render process, service, memory, CPU, trap, uptime, and kernel log views
- Render per-process status files
- Render per-process RKX mapping files
- Notify `svcmgtd` with a service ready ACK after startup

## RKX Metadata

- `stack_pages = 4`
- capabilities:
  - `sys_process_list`

`procfsd` needs process-list access so it can render `/proc/processes`,
`/proc/<pid>/status`, and `/proc/<pid>/rkx_map`.

## Provided Paths

```text
/proc/uptime
/proc/meminfo
/proc/cpuinfo
/proc/processes
/proc/services
/proc/traps
/proc/kmsg
/proc/<pid>/status
/proc/<pid>/rkx_map
```

## Request Flow

1. An app calls a normal filesystem operation for a `/proc` path
2. `fsd` recognizes the `/proc` prefix
3. `fsd` forwards the request to `procfsd`
4. `procfsd` renders the virtual file or directory entries
5. `fsd` returns the result through the usual FS response path

## Boundaries and Notes

- Output is capped by the IPC message buffer
- `/proc` files are generated on request and are not stored on disk
- `/proc/<pid>/rkx_map` is available only for user RKX processes
