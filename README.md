<p>
  <img src="./assets/Rk-C_logo.png" alt="Rk-C Logo" width="250">
</p>

Rk-C is an experimental RISC-V 64-bit microkernel-style operating system written
mainly in Nim.

The kernel keeps the privileged core small: boot, traps, scheduling, virtual
memory, user process execution, IPC, and the minimal hardware-facing syscalls.
System policy and device-facing subsystems are moved into U-mode servers, so the
running system is built from cooperating services such as `svcmgtd`,
`procmgtd`, `fsd`, `blockd`, `procfsd`, `netd`, and `userd`.

Rk-C currently boots on QEMU `virt` through OpenSBI, runs protected U-mode
programs, supports a shell-driven userland, and includes enough filesystem,
process, service, account, and networking features to exercise the
microkernel design end-to-end.

![ss](./assets/terminal.png)

## Highlights

Kernel and architecture:

- RISC-V 64-bit S-mode kernel for QEMU `virt`
- OpenSBI `fw_jump` boot flow into `kernel.elf`
- Sv39 paging with per-process address spaces
- Timer-driven preemptive scheduling and process lifecycle management
- U-mode execution with trap/syscall dispatch and fault reporting
- RKX user executable loader with text, rodata, data, bss, and stack mappings
- W^X user mappings and non-executable user stacks
- User pointer validation and hardened usercopy helpers
- File descriptors, standard streams, pipes, `dup2`, and pollable events
- Entropy syscall used by TLS client code
- Syscall tracing with global, per-PID, and per-command modes

Microkernel and service model:

- Structured IPC packets and request/reply helpers
- Service registry with ready ACKs, restart/degraded state, status, and logs
- Root-only service control through RKX metadata and IPC sender credentials
- Userland service manager: `svcmgtd`
- Userland process manager: `procmgtd`
- Userland block server: `blockd`
- Userland filesystem server: `fsd`
- Userland procfs server: `procfsd`
- Userland network server: `netd`
- Userland account database server: `userd`

Filesystem and accounts:

- Disk-backed root filesystem plus appfs-packed command images
- tmpfs mount for `/tmp`
- procfs mount for `/proc`
- Device-like files under `/dev` for standard I/O
- Unix-like file ownership and mode checks
- `/etc/passwd`, `/etc/group`, and PBKDF2-HMAC-SHA256 `/etc/shadow`
- Login flow that starts a shell under the authenticated UID/GID

Networking:

- VirtIO MMIO network device support
- MAC address discovery and RX/TX queue handling
- ARP, IPv4, ICMP, UDP, DNS, TCP, and HTTP client support
- Experimental TLS 1.3 HTTPS client path
- TAP networking by default, with QEMU user networking as an option

Userland:

- Interactive shell with cwd-aware prompt, history, background jobs, pipes, and
  output redirection
- Core commands such as `ls`, `cat`, `mkdir`, `rm`, `rmdir`, `cp`, `mv`, `df`,
  `ps`, `kill`, `svc`, `id`, `chmod`, `chown`, `edit`, `stracectl`, and `dmesg`
- Network tools such as `ping`, `nslookup`, `tcpcheck`, and `curl`
- RKX metadata inspection with `rkxinfo`
- QEMU smoke tests for apps, services, permissions, faults, IPC, pipes, and
  network paths

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
  +-- RKX loader
  +-- IPC transport and service registry
  +-- low-level VirtIO MMIO access
  |
  +-- /bin/svcmgtd
        |
        +-- /bin/procmgtd
        +-- /bin/blockd
        +-- /bin/fsd
        +-- /bin/procfsd
        +-- /bin/netd
        |
        +-- /bin/shell
```

Design details live under [docs/design](docs/design/README.md).

## Repository Layout

```text
src/
  arch/riscv64/        RISC-V assembly and CSR/SBI helpers
  kernel/              Kernel implementation
  lib/                 Shared kernel/user ABI types and helpers
  user/
    apps/              User commands and test-only apps
    lib/               User runtime, syscall, IPC, and protocol helpers
    server/            Userland servers
scripts/
  make_rkx.py          Converts user ELF files into RKX images
  pack_appfs.py        Packs RKX images into the disk image
  test_apps.py         Boots QEMU and smoke-tests user apps
docs/
  design/              Subsystem design notes
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

Useful variants:

```bash
make build-bins
make build-test-bins
```

## Run

```bash
make run
```

Run without a VirtIO network device to test degraded optional-service boot:

```bash
make degraded-run
```

Start QEMU paused with a GDB server:

```bash
make qemu-debug
```

Override the GDB port with:

```bash
make qemu-debug GDB_PORT=1235
```

## Tests

Run the QEMU app smoke test suite:

```bash
make test-apps
```

Useful variants:

```bash
python3 scripts/test_apps.py --no-build
python3 scripts/test_apps.py --skip-network-smoke
python3 scripts/test_apps.py --keep-test-disk
python3 scripts/test_apps.py --tap-if tap0 --host-ip 10.0.1.1
```

The test runner uses `bin/test-disk.img` and removes it after completion unless
`--keep-test-disk` is passed.

## Networking

`make run` defaults to TAP networking:

```text
QEMU_NET=tap
QEMU_TAP_IF=tap0
```

The guest default network settings are:

```text
guest IP:    10.0.1.10
gateway:     10.0.1.1
netmask:     255.255.255.0
DNS server:  8.8.8.8
```

Host setup example:

```bash
sudo ip tuntap add dev tap0 mode tap user "$USER"
sudo ip link set tap0 up
sudo ip addr add 10.0.1.1/24 dev tap0
sudo sysctl -w net.ipv4.ip_forward=1
sudo iptables -t nat -A POSTROUTING -s 10.0.1.0/24 -j MASQUERADE
```

QEMU user networking is also available:

```bash
make run QEMU_NET=user
```

Print the current networking notes:

```bash
make net-host-help
```

## Shell Examples

```text
Rk-C:/$ help
Rk-C:/$ svc status
Rk-C:/$ ps -l
Rk-C:/$ ls /proc
Rk-C:/$ rkxinfo curl
Rk-C:/$ date > /tmp/now.txt
Rk-C:/$ cat /tmp/now.txt | cat
Rk-C:/$ ping 10.0.1.1
Rk-C:/$ curl http://example.com/
Rk-C:/$ shutdown
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
