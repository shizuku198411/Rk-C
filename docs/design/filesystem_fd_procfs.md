# Filesystem, FD, and Procfs

Rk-C has a small filesystem stack with a userland filesystem service.

## Storage Layout

- root filesystem metadata and file data live on the VirtIO block disk
- `/bin` is appfs-packed from RKX images
- `/tmp` is tmpfs-backed
- `/proc` is served by `procfsd`

`blockd` owns raw block access. `fsd` owns raw filesystem operations.

## Permissions

Normal filesystem syscalls are checked with the caller process identity:

- `uid`
- primary `gid`
- file mode bits

RKX capabilities are intentionally separate from file permissions. Root can
bypass normal file mode checks, but root does not automatically gain raw block,
raw filesystem, raw network, trace, or service-management capabilities.

Ownership changes are exposed through `chown`, which is root-only. Mode changes
are exposed through `chmod`, which is allowed for root or the file owner.
`/tmp` uses sticky-directory behavior so users cannot remove each other's files
from the public tmpfs mount.

## FS Service

`fsd` serves:

- directory listing
- mkdir
- unlink
- rmdir
- read file
- write file
- file size
- range read

Range read exists so fd reads can fetch only the requested file slice. This is
important for large `/bin/*.rkx` files and tools such as `rkxinfo`.

## File Descriptors

The fd layer supports:

- `open`
- `read`
- `write`
- `close`
- `lseek`
- pipes
- `dup2`
- stdin/stdout/stderr devices

Shell redirection and simple pipelines are built on fd operations.

FD read/write currently re-evaluates filesystem permissions on each operation.
This means a later `chmod` affects already-open file descriptors immediately.
That is simpler than Unix-style open-time permission snapshots and keeps the
authorization behavior explicit while the FS service boundary is still evolving.

If Rk-C later wants closer Unix compatibility, `FdEntry` can grow cached
`readAllowed` / `writeAllowed` bits set at `open` time.

## Procfs

`procfsd` serves `/proc` through the filesystem service boundary.

Useful paths:

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
