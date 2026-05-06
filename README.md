# Rk-C Nim Kernel

```text
╔═══════════════════════════════════╗
║  ██████╗  ██╗  ██╗       ██████╗  ║
║  ██╔══██╗ ██║ ██╔╝      ██╔════╝  ║
║  ██████╔╝ █████╔╝ █████╗██║       ║
║  ██╔══██╗ ██╔═██╗ ╚════╝██║       ║
║  ██║  ██║ ██║  ██╗      ╚██████╗  ║
║  ╚═╝  ╚═╝ ╚═╝  ╚═╝       ╚═════╝  ║
╠═══════════════════════════════════╣
║  version: 0.1.0                   ║
╚═══════════════════════════════════╝
```

Rk-C is an experimental microkernel-style operating system for RISC-V 64-bit,
implemented mainly in Nim.

It targets QEMU's `virt` machine, boots through OpenSBI, enters S-mode as an ELF
kernel, and runs standalone U-mode user programs loaded from a disk image.

## Current Status

This project is still small and experimental, but the core userspace/server
architecture is now in place:

- RISC-V 64-bit S-mode kernel
- U-mode process execution
- syscall and trap handling
- simple process scheduler
- per-process address spaces with Sv39
- disk image based `/bin`
- tmpfs-backed `/tmp`
- structured IPC packets
- userland service processes
- shell and standalone user commands

## Architecture

```text
OpenSBI
  |
  v
kernel.elf
  |
  +-- scheduler
  +-- syscall/trap layer
  +-- service registry
  +-- low-level memory/process primitives
  |
  +-- /bin/svcmgtd
        |
        +-- /bin/procmgtd
        +-- /bin/blockd
        +-- /bin/fsd
        |
        +-- /bin/shell
```

The kernel keeps the low-level mechanisms, while higher-level policy is moving
toward userland services.

### Kernel Responsibilities

- bootstrapping from OpenSBI
- trap entry and syscall dispatch
- page allocation and Sv39 page table management
- process table and context switching
- service registry
- raw block and filesystem fallback paths
- user memory copy validation

### Userland Servers

| Server | Path | Role |
| --- | --- | --- |
| `svcmgtd` | `/bin/svcmgtd` | Service manager. Starts and monitors core services. |
| `procmgtd` | `/bin/procmgtd` | Process manager. Handles `ps` and `kill` requests. |
| `blockd` | `/bin/blockd` | Block device server. Handles block read/write requests. |
| `fsd` | `/bin/fsd` | Filesystem server. Handles file and directory requests. |

### User Applications

| Command | Description |
| --- | --- |
| `shell` | Interactive shell |
| `ls` | List directory entries |
| `cat` | Print file contents |
| `mkdir` | Create directory |
| `rm` | Remove file |
| `rmdir` | Remove empty directory |
| `ps` | Show processes through `procmgtd` |
| `kill` | Request process termination through `procmgtd` |
| `date` | Show RTC date/time |
| `edit` | Small terminal file editor |
| `ipc` | IPC test command |
| `svc` | Service management command |

## Features

- OpenSBI-based boot on QEMU `virt`
- RISC-V trap entry in assembly
- Nim syscall dispatch and kernel logic
- S-mode kernel / U-mode userland split
- timer interrupt support
- round-robin-style scheduling
- kernel and user process support
- user process spawning with parent metadata inheritance groundwork
- per-process `cwd`
- structured IPC packet type
- common IPC request/reply helper code
- service registry with service availability checks
- service restart through `svcmgtd`
- protected service kill policy
- VirtIO MMIO block device support
- disk-backed root filesystem
- appfs-packed `/bin`
- VFS-style mount points
- tmpfs mounted at `/tmp`
- shell prompt with current working directory
- terminal editor with cursor movement and save/exit controls

## Repository Layout

```text
src/
  arch/riscv64/      RISC-V assembly and CSR/SBI helpers
  kernel/            Kernel implementation
    init/            Bootstrap code
    mm/              Memory, paging, usercopy
    task/            Process, scheduler, exec
    syscall/         Syscall implementation grouped by subsystem
    fs/              Kernel filesystem and VFS pieces
    service/         Kernel service registry
    dev/             Console, timer, RTC
  lib/               Shared kernel/user ABI types and helpers
  user/
    apps/            User commands
    server/          Userland servers
    lib/             Userland syscall, IPC, IO helpers
scripts/
  pack_appfs.py      Packs user binaries into the disk image
```

## Requirements

- QEMU with RISC-V system emulation
- OpenSBI
- Nim 2.2.10
- clang / lld / LLVM tools
- Python 3
- GNU make
- RISC-V GNU toolchain for building OpenSBI

On Ubuntu-like systems:

```bash
sudo apt install -y \
  qemu-system-misc \
  make \
  clang \
  lld \
  llvm \
  python3 \
  gcc-riscv64-linux-gnu
```

## Nim

The current Makefile expects Nim at:

```text
~/nim-2.2.10/bin/nim
```

If your Nim binary is somewhere else, update `NIM` in `Makefile`.

For a local install:

```bash
cd ~
wget https://nim-lang.org/download/nim-2.2.10-linux_x64.tar.xz
tar Jxf nim-2.2.10-linux_x64.tar.xz
~/nim-2.2.10/bin/nim --version
```

## OpenSBI

The QEMU run target expects:

```text
opensbi/build/platform/generic/firmware/fw_jump.bin
```

Build it with:

```bash
git clone https://github.com/riscv-software-src/opensbi.git
cd opensbi
git checkout v1.8.1
export CROSS_COMPILE=riscv64-linux-gnu-
make PLATFORM=generic
```

## Build

```bash
make build
```

This builds:

- `bin/kernel.elf`
- user applications and servers as freestanding RISC-V binaries
- `bin/disk.img` with packed `/bin` contents

## Run

```bash
make run
```

The kernel boots through OpenSBI, starts the service manager, waits for required
services, and then starts the shell.

Example boot flow:

```text
[svcmgtd] service management server started pid=3
[svcmgtd] service started procmgtd pid=4
[svcmgtd] service started blockd pid=5
[svcmgtd] service started fsd pid=6

[shell] Rk-C shell started pid=7
```

## Shell Examples

```text
Rk-C:/$ help
Rk-C:/$ svc list
Rk-C:/$ ps
Rk-C:/$ ls /
Rk-C:/$ mkdir /tmp/demo
Rk-C:/$ edit /tmp/hello.txt
Rk-C:/$ cat /tmp/hello.txt
Rk-C:/$ svc restart fsd
Rk-C:/$ shutdown
```

## Debug Run

```bash
make qemu-debug
```

This starts QEMU with `-S -gdb tcp::1234`.

Override the GDB port with:

```bash
make qemu-debug GDB_PORT=1235
```

## Notes

- This is a learning and research kernel, not a production OS.
- The ABI and internal service protocols are still evolving.
- Many subsystems intentionally start small and are being pushed toward
  userland services over time.
