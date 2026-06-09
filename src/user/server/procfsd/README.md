# procfsd

`procfsd` is the userspace procfs server.

It provides `/proc`-style virtual files through IPC behind `fsd`, so normal file
commands can inspect kernel and process state with paths such as
`/proc/processes` and `/proc/<pid>/status`.

Its syscall snapshot workspaces are owned by Nim ORC through the Rk-C `osalloc`
bridge. Virtual-file text is built in a request-local managed string and copied
into the response packet before being released. The request and response packets
remain fixed-size objects because their layout is the IPC ABI shared with `fsd`.

## Responsibilities

- Serve `/proc` directory listings
- Render process, service, memory, CPU, mount, trap, uptime, and kernel log views
- Render per-process status files
- Render per-process RKX mapping files
- Render per-process wait and fd diagnostic files
- Notify `svcmgtd` with a service ready ACK after startup

## RKX Metadata

- `stack_pages = 4`
- capabilities:
  - `sys_process_list`

`procfsd` needs process-list access so it can render `/proc/processes`,
`/proc/<pid>/status`, `/proc/<pid>/wait`, and `/proc/<pid>/rkx_map`.

## Provided Paths

```text
/proc/uptime
/proc/meminfo
/proc/cpuinfo
/proc/processes
/proc/services
/proc/mounts
/proc/traps
/proc/kmsg
/proc/fsinfo
/proc/tty
/proc/rkx_trust
/proc/<pid>/status
/proc/<pid>/wait
/proc/<pid>/rkx_map
/proc/<pid>/fd
/proc/<pid>/fd/<fd>
```

## Request Flow

1. An app calls a normal filesystem operation for a `/proc` path
2. `fsd` recognizes the `/proc` prefix
3. `fsd` forwards the request to `procfsd`
4. `procfsd` renders the virtual file or directory entries
5. `fsd` returns the result through the usual FS response path

## Boundaries and Notes

- Output is capped by the IPC message buffer
- Snapshot workspaces are allocated once as stable ORC-owned sequences and are not resized while syscall pointer views are active
- Virtual-file formatting uses a request-local ORC-managed string capped at the fixed IPC payload size
- `/proc` files are generated on request and are not stored on disk
- `/proc/<pid>/rkx_map` is available only for user RKX processes
- `/proc/<pid>/wait` reports the current wait target snapshot; runnable or zombie processes usually report `none`
