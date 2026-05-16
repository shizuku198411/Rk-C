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
kernel, and runs U-mode programs packaged as `rkx` images from a disk-backed
`/bin`.

The project is intentionally small, but it already has a real userspace/server
shape: core mechanisms remain in the kernel, while process management, block
I/O, filesystem operations, service management, and networking are served from
userland processes over IPC.

## Current Status

- RISC-V 64-bit S-mode kernel on QEMU `virt`
- OpenSBI `fw_jump` boot flow
- Sv39 paging with per-process address spaces
- U-mode process execution from `rkx` images
- `rkx` segment permissions:
  - text: user RX
  - rodata: user R
  - data/bss: user RW
  - stack: user RW, NX
- trap entry, syscall dispatch, and user/kernel fault split
- preemptive timer-driven scheduling for user processes
- hardened usercopy range checks for syscall pointer arguments
- structured IPC packets and request/reply helpers
- service registry with ready ACKs, restart support, and degraded optional services
- userland servers for process, block, filesystem, and network services
- appfs-packed `/bin`
- VFS-style mount points with tmpfs-backed `/tmp`
- shell with standalone command binaries, pipes, redirection, and background apps
- VirtIO MMIO block and network devices
- ARP, IPv4, ICMP, UDP, DNS, TCP, HTTP, and experimental HTTPS/TLS client paths
- QEMU smoke tests for boot, services, user apps, W^X, NX stack, and user pointer rejection

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
  +-- rkx loader
  +-- IPC transport and service registry
  +-- low-level VirtIO MMIO access
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

The boot task starts `svcmgtd`, waits for required services to become ready,
waits for optional services until timeout, marks unavailable optional services
as degraded, and then starts the interactive shell.

Required services:

- `svcmgtd`
- `procmgtd`
- `blockd`
- `fsd`

Optional service:

- `netd`

## Kernel Responsibilities

- bootstrapping from OpenSBI
- trap entry and syscall dispatch
- page allocation and Sv39 page table management
- process table, process lifecycle, and context switching
- preemptive timer scheduling
- safe user memory copy validation
- `rkx` image loading and segment permission mapping
- service registry and service availability checks
- IPC queueing and request/reply transport
- raw fallback paths while required services are unavailable during boot
- low-level VirtIO MMIO access for block and network devices

## Userland Servers

| Server | Path | Role |
| --- | --- | --- |
| `svcmgtd` | `/bin/svcmgtd` | Starts, monitors, lists, and restarts registered services. |
| `procmgtd` | `/bin/procmgtd` | Handles process listing and process termination requests. |
| `blockd` | `/bin/blockd` | Serves block read/write requests over IPC. |
| `fsd` | `/bin/fsd` | Serves file and directory operations over IPC. |
| `netd` | `/bin/netd` | Serves network operations over IPC. Optional; boot may continue degraded without it. |

## User Applications

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
| `stracectl` | Syscall trace control command |

Test-only app:

| Command | Description |
| --- | --- |
| `faultcheck` | Packed only by `make test-apps`; checks invalid user CString rejection, user text W^X, and NX stack behavior. |

## RKX User Image Format

User programs are linked as ELF files, then converted by `scripts/make_rkx.py`
into compact `rkx` images for appfs.

`rkx` stores:

- magic/version/header size
- entry virtual address
- text segment VA, file offset, file size, memory size
- rodata segment VA, file offset, file size, memory size
- data segment VA, file offset, file size, memory size
- bss VA and memory size

The kernel loader validates:

- magic/version/header size
- file ranges
- page alignment
- expected user VA window
- entry inside text
- segment non-overlap

The loader maps each segment with separate permissions, avoiding the old
single RWX user image mapping.

## Repository Layout

```text
src/
  arch/riscv64/        RISC-V assembly and CSR/SBI helpers
  kernel/              Kernel implementation
    dev/               Console, timer, RTC
    fs/                Kernel filesystem and VFS pieces
    init/              Bootstrap code
    lib/               Kernel-only helper modules
    mm/                Memory, paging, usercopy
    net/               Low-level network device support
    service/           Kernel service registry
    syscall/           Syscall implementation grouped by subsystem
    task/              Process, scheduler, exec, rkx loader
    trap/              Trap and syscall entry logic
  lib/                 Shared kernel/user ABI types and helpers
  user/
    apps/              User commands and test-only apps
    lib/
      core/            User syscall, IO, path, string, CLI helpers
      ipc/             User IPC helpers and service clients
      net/             User network clients and protocol helpers
      runtime/         User entry and syscall assembly
    server/            Userland servers
scripts/
  make_rkx.py          Converts user ELF files into rkx images
  pack_appfs.py        Packs rkx images into the disk image
  test_apps.py         Boots QEMU and smoke-tests user apps
docs/
  design/              Design notes
  review/              Review notes and follow-up checklists
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
- user applications and servers as freestanding RISC-V ELF files
- user applications and servers as `bin/*.rkx`
- `bin/disk.img` with packed `/bin` contents

Build kernel and rkx images without repacking the disk image:

```bash
make build-bins
```

Build the test-only app images too:

```bash
make build-test-bins
```

## Run

```bash
make run
```

The kernel boots through OpenSBI, starts the service manager, waits for required
service ready ACKs, waits for optional services up to timeout, and then starts
the shell.

Example boot flow:

```text
[svcmgtd] service management server started pid=3
[svcmgtd] service started procmgtd pid=4
[svcmgtd] service ready procmgtd pid=4
[svcmgtd] service started blockd pid=5
[svcmgtd] service ready blockd pid=5
[svcmgtd] service started fsd pid=6
[svcmgtd] service ready fsd pid=6
[svcmgtd] service started netd pid=7
[svcmgtd] service ready netd pid=7
Rk-C:/$
```

Run without a VirtIO network device to test degraded optional-service boot:

```bash
make degraded-run
```

## Tests

Run the QEMU app smoke test suite:

```bash
make test-apps
```

The test runner:

- builds normal and test-only rkx images
- copies `bin/disk.img` to `bin/test-disk.img`
- packs `/bin/faultcheck` only into the test disk
- boots QEMU with the test disk
- verifies boot, shell commands, all app help paths, FS operations, pipes,
  redirection, service/process commands, network smoke paths, W^X, NX stack, and
  invalid user CString rejection
- prints expected values and summarized actual output for each test
- deletes `bin/test-disk.img` after completion

Useful variants:

```bash
python3 scripts/test_apps.py --no-build
python3 scripts/test_apps.py --skip-network-smoke
python3 scripts/test_apps.py --keep-test-disk
```

## Networking

`make run` defaults to TAP networking:

```text
QEMU_NET=tap
QEMU_TAP_IF=tap0
```

The guest creates default static network settings if `/etc/interface.conf` and
`/etc/resolve.conf` are missing:

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

QEMU user networking is also available:

```bash
make run QEMU_NET=user
```

External ICMP may timeout with QEMU user networking, so TAP is the recommended
mode for `ping` and general network testing.

Print the current networking notes:

```bash
make net-host-help
```

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

## Shell Examples

```text
Rk-C:/$ help
Rk-C:/$ svc list
Rk-C:/$ ps
Rk-C:/$ ls /
Rk-C:/$ mkdir /tmp/demo
Rk-C:/$ date > /tmp/now.txt
Rk-C:/$ cat /tmp/now.txt | cat
Rk-C:/$ edit /tmp/hello.txt
Rk-C:/$ ping 10.0.2.2
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

## Clean

```bash
make clean
```

## Notes

- This is a learning and research kernel, not a production OS.
- The ABI and internal service protocols are still evolving.
- The HTTPS/TLS path does not validate certificates yet.
- The network stack is intentionally small and experimental.
- Many subsystems intentionally start small and are being pushed toward
  userland services over time.
