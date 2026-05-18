# Filesystem, FD, and Procfs

Rk-C has a small filesystem stack with a userland filesystem service.

## Storage Layout

- root filesystem metadata and file data live on the VirtIO block disk
- `/bin` is appfs-packed from RKX images
- `/tmp` is tmpfs-backed
- `/proc` is served by `procfsd`

`blockd` owns raw block access. `fsd` owns raw filesystem operations.

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

