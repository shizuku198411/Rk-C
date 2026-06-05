# Filesystem, FD, and Procfs

Rk-C has a small filesystem stack built around a service boundary. The kernel provides bootstrapping, raw device access, FD bookkeeping, and syscall validation. `blockd`, `fsd`, and `procfsd` provide userland policy and content.

## Storage Layout

The active disk layout is selected by `src/platform/fs_layout.nim`.

QEMU uses the development disk image produced by the build system. Milk-V uses SD-card backed storage and the Milk-V block backend.

```text
block backend
  -> partition/layout selection
  -> root filesystem
  -> appfs packed RKX images
  -> tmpfs and procfs mounts
```

`/bin` is populated from appfs. `/tmp` is tmpfs-backed. `/proc` is served by procfsd. `/dev` exposes console/TTY device paths used by the FD layer.

## Block and Filesystem Services

`blockd` owns raw block requests after registration.

`fsd` owns filesystem operations:

- directory listing
- mkdir
- unlink
- rmdir
- read file
- write file
- write range
- rename
- chmod
- chown
- file size
- range read

Range read exists so FD reads and tools such as `rkxinfo` can fetch only the requested slice instead of copying full files.

## Permissions

Filesystem permission checks use process identity:

- UID
- primary GID
- file owner
- file group
- mode bits

Capabilities are intentionally separate from filesystem permissions. Root can bypass normal file mode checks, but root does not automatically gain raw block, raw filesystem, raw network, trace, shutdown, or service-manager capabilities.

Important behavior:

- `chmod` is allowed for root or the file owner.
- `chown` is root-only.
- `/tmp` uses sticky-directory behavior so users cannot remove each other's files from the public tmpfs mount.
- `/home` is root-owned.
- `/home/rkc` is owned by `rkc:rkc`.

## Default System Files

Boot and services create or maintain:

```text
/etc/os-release
/etc/passwd
/etc/shadow
/etc/group
/etc/interface.conf
/home/rkc
```

`/etc/os-release` is created as `root:root` with mode `0644`.

## File Descriptors

The FD layer supports:

- `open`
- `read`
- `write`
- `close`
- `lseek`
- `pipe`
- `dup2`
- stdin/stdout/stderr
- `/dev/stdin`
- `/dev/stdout`
- `/dev/stderr`
- `/dev/console`
- `/dev/tty0`

Shell redirection and simple pipelines are implemented through FD setup before child exec.

```text
ls > /tmp/list.txt
  -> open output file
  -> dup2(file_fd, stdout)
  -> exec /bin/ls

cat a | wc
  -> pipe()
  -> dup2(write_end, stdout) for left child
  -> dup2(read_end, stdin) for right child
```

FD read/write currently re-evaluates filesystem permissions on each operation. This is simpler than Unix open-time permission snapshots and keeps authorization behavior explicit while the service boundary continues to evolve.

## TTY and Console Files

`tty0` is the single runtime TTY. It is backed by a kernel RX ring and the active platform console backend.

```text
UART/SBI input
  -> tty0 RX ring
  -> fd 0 or /dev/stdin
```

TTY state and statistics are visible through `/proc/tty`.

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
/proc/fsinfo
/proc/tty
/proc/<pid>/status
/proc/<pid>/rkx_map
```

Large virtual files use chunked read paths so procfs does not need to materialize full output for every file-size query.

## Design Constraints

- Raw fallback is only for pre-service bootstrap.
- After a service registers, normal callers must go through service IPC.
- Keep FD logic generic; app-specific redirection behavior should not be implemented in individual commands.
- Avoid copying whole files when range reads or procfs chunking can provide the requested slice.
