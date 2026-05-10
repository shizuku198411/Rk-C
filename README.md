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

The project is intentionally small, but it already has a real userspace/server
shape: core mechanisms remain in the kernel, while filesystems, block I/O,
process management, service management, and networking are moving toward
userland servers.

## Current Status

- RISC-V 64-bit S-mode kernel
- U-mode user process execution
- Sv39 paging with per-process address spaces
- timer interrupt based scheduling
- syscall and trap handling
- structured IPC packets and request/reply helpers
- service registry and service manager
- userland servers for process, block, filesystem, and network services
- disk image packed `/bin`
- VFS-style mount points with tmpfs-backed `/tmp`
- shell with standalone command binaries
- VirtIO MMIO block and network devices
- ARP, IPv4, ICMP, UDP, DNS, TCP, HTTP, and experimental HTTPS/TLS client paths

## Architecture

```text
OpenSBI
  |
  v
kernel.elf
  |
  +-- trap/syscall dispatch
  +-- scheduler and process table
  +-- memory manager and Sv39 paging
  +-- service registry
  +-- low-level VirtIO device access
  |
  +-- /bin/svcmgtd
        |
        +-- /bin/procmgtd
        +-- /bin/blockd
        +-- /bin/fsd
        +-- /bin/netd
        |
        +-- /bin/shell
```

The boot task starts `svcmgtd`, waits until required services are registered and
available, and then starts the interactive shell. After the boot sequence is
finished, the temporary boot process is removed from the process table.

### Kernel Responsibilities

- bootstrapping from OpenSBI
- trap entry and syscall dispatch
- page allocation and Sv39 page table management
- process table, process lifecycle, and context switching
- safe user memory copy validation
- service registry
- IPC queueing and request/reply transport
- raw fallback paths while required services are not registered yet
- low-level VirtIO MMIO access for block and network devices

### Userland Servers

| Server | Path | Role |
| --- | --- | --- |
| `svcmgtd` | `/bin/svcmgtd` | Starts, monitors, lists, and restarts registered services. |
| `procmgtd` | `/bin/procmgtd` | Handles process listing and process termination requests. |
| `blockd` | `/bin/blockd` | Serves block read/write requests over IPC. |
| `fsd` | `/bin/fsd` | Serves file and directory operations over IPC. |
| `netd` | `/bin/netd` | Serves network operations over IPC. |

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
| `ping` | ICMP echo request through `netd` |
| `nslookup` | DNS A record lookup through UDP/netd |
| `tcpcheck` | TCP connectivity test command |
| `curl` | HTTP/HTTPS client command |

## Features

- OpenSBI-based boot on QEMU `virt`
- RISC-V trap entry and context switching in assembly
- Nim syscall dispatch and kernel logic
- S-mode kernel / U-mode userland split
- round-robin-style multitasking
- user process spawning with parent metadata inheritance groundwork
- per-process current working directory
- structured IPC packet ABI shared by kernel and userland
- common user/kernel IPC request/reply helpers
- service availability checks and service restart support
- protected service management policy
- VirtIO MMIO block device support
- VirtIO MMIO network device support
- appfs-packed `/bin`
- disk-backed root filesystem
- VFS-style mount points
- tmpfs mounted at `/tmp`
- shell prompt with current working directory
- terminal editor with cursor movement and save/exit controls
- ARP, IPv4, ICMP, UDP, DNS, TCP, HTTP, and HTTPS client experiments

## Networking

`make run` defaults to TAP networking:

```text
QEMU_NET=tap
QEMU_TAP_IF=tap0
```

The guest currently uses static network settings:

```text
guest IP:    10.0.2.15
gateway:     10.0.2.2
netmask:     255.255.255.0
DNS server:  8.8.8.8
```

Host setup example:

```bash
sudo ip tuntap add dev tap0 mode tap user "$USER"
sudo ip link set tap0 up
sudo ip addr add 10.0.2.2/24 dev tap0
sudo sysctl -w net.ipv4.ip_forward=1
sudo iptables -t nat -A POSTROUTING -s 10.0.2.0/24 -j MASQUERADE
```

QEMU user networking is still available:

```bash
make run QEMU_NET=user
```

External ICMP may timeout with QEMU user networking, so TAP is the recommended
mode for `ping` and general network testing.

## HTTPS/TLS Status

The HTTPS path is experimental. It is intended as a learning implementation and
currently focuses on fetching HTTPS content through the userspace network stack.

Implemented pieces include:

- TLS 1.3 client handshake groundwork
- X25519 key exchange
- HKDF/SHA-256 helpers
- ChaCha20-Poly1305 AEAD
- HTTP over the TLS transport path

Certificate trust validation, mTLS, entropy syscall integration, and broader
cipher suite support are future work.

## Repository Layout

```text
src/
  arch/riscv64/        RISC-V assembly and CSR/SBI helpers
  kernel/              Kernel implementation
    dev/               Console, timer, RTC
    fs/                Kernel filesystem and VFS pieces
    init/              Bootstrap code
    mm/                Memory, paging, usercopy
    net/               Low-level network device support
    service/           Kernel service registry
    syscall/           Syscall implementation grouped by subsystem
    task/              Process, scheduler, exec
    trap/              Trap and syscall entry logic
  lib/                 Shared kernel/user ABI types and helpers
  user/
    apps/              User commands
    lib/
      core/            User syscall, IO, path, string helpers
      ipc/             User IPC helpers and service clients
      net/             User network clients and protocol helpers
      runtime/         User entry and syscall assembly
    server/            Userland servers
scripts/
  pack_appfs.py        Packs user binaries into the disk image
docs/
  design/              Design notes
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
[svcmgtd] service started netd pid=7

[shell] Rk-C shell started
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
Rk-C:/$ ping 8.8.8.8
Rk-C:/$ nslookup example.com
Rk-C:/$ curl http://example.com/
Rk-C:/$ curl https://example.com/
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

## Network Help

```bash
make net-host-help
```

This prints the current TAP and QEMU user-networking setup notes from the
Makefile.

## Clean

```bash
make clean
```

## Notes

- This is a learning and research kernel, not a production OS.
- The ABI and internal service protocols are still evolving.
- The HTTPS/TLS path does not validate certificates yet.
- Many subsystems intentionally start small and are being pushed toward
  userland services over time.
