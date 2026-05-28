<p>
  <img src="./assets/Rk-C_logo.png" alt="Rk-C Logo" width="250">
</p>

[Official Documentations is here!](https://shizuku198411.github.io/Rk-C-Doc/)

Rk-C is an experimental RISC-V 64-bit microkernel prototype written mainly in
Nim.

The project keeps the S-mode kernel minimal, delegating policy and device-facing
functionality to isolated U-mode services. It combines a small privileged core
with a userland service model that includes process management, filesystem,
networking, and account services.

Rk-C currently boots on QEMU `virt` with OpenSBI, runs protected U-mode
processes, offers a shell-driven user environment, and includes enough
filesystem, service, and networking behavior to demonstrate the microkernel
architecture end-to-end.

![ss](./assets/terminal_overview.png)

## Highlights

Rk-C is an experimental Nim-based RISC-V microkernel prototype that keeps the privileged kernel small and pushes policy into cooperating U-mode services.

- Core kernel features include booting on QEMU `virt` via OpenSBI, Sv39 virtual memory, preemptive scheduling, trap/syscall dispatch, and a user-mode process execution model.
- The system is organized as a microkernel plus userland servers, with a service registry, IPC-based request/reply transport, and userland managers for processes, services, storage, networking, and accounts.
- The user environment provides a shell-centric userland, disk-backed root filesystem with `/tmp` and `/proc`, Unix-like permissions/accounts, command binaries, and basic networking tools.
- Networking support includes VirtIO MMIO networking, TAP/QEMU user networking, IPv4 stack components, DNS, TCP, HTTP client support, and an experimental TLS 1.3 path.
- The project includes tooling for building RKX executables, packaging app images, and running smoke tests to verify kernel, IPC, filesystem, service, and networking behavior.

## Architecture

```text
          +----------------------------------------+
          |            OpenSBI / Boot loader       |
          +----------------------------------------+
                           |
                           v
          +----------------------------------------+
          |              Kernel (S-mode)           |
          |                                        |
          |  - Exception / trap entry              |
          |  - Syscall dispatch                    |
          |  - Scheduler & process table           |
          |  - Sv39 virtual memory manager         |
          |  - RKX executable loader               |
          |  - IPC transport & service registry    |
          |  - VirtIO MMIO device support          |
          +----------------------------------------+
                           |
          +----------------+----------------+----------------+
          |                |                |                |
          v                v                v                v
 +----------------+ +----------------+ +----------------+ +----------------+
 | User process   | | User process   | | Userland       | | Userland       |
 | (U-mode)       | | (U-mode)       | | server         | | server         |
 | - RKX image    | | - RKX image    | | - svcmgtd      | | - procmgtd     |
 | - syscall      | | - IPC client   | | - fsd / blockd | | - netd / userd |
 |   interface    | | - threads      | | - procfsd      | | - shell        |
 +----------------+ +----------------+ +----------------+ +----------------+
          ^                ^                ^                ^
          |                |                |                |
          +----------------+----------------+----------------+
                           |
             IPC request/reply + shared service registry
```

- The kernel runs in S-mode and keeps privileged functionality small.
- User workloads and services run in U-mode as isolated processes with separate address spaces.
- Syscalls and traps are dispatched by the kernel, which also manages paging, scheduling, and IPC transport.
- U-mode services cooperate through a registry-based IPC model, and can be restarted or monitored from the service manager.

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
.workshop/
  rkc-base/            Canonical Workshop SDK for the Rk-C dev environment
```

## Recommended Development Environment

Rk-C can be built, tested, and run inside a Canonical [Workshop](https://ubuntu.com/workshop) sandbox.

This is the recommended setup because the project depends on several tools that
often differ between host environments:

* Nim 2.2.10
* clang / lld / LLVM tools
* QEMU RISC-V system emulation
* OpenSBI
* RISC-V GNU toolchain for building OpenSBI
* Python 3 and GNU make

The Workshop SDK prepares these dependencies inside the sandbox and builds the
OpenSBI firmware expected by the Makefile.

### install lxd and Workshop

Install lxd and workshop using `snap`
```bash
sudo snap install --channel=6/stable lxd
sudo snap install --classic workshop
```

### Launch the Workshop environment

From the repository root:

```bash
workshop launch
```

after launch is completed, check the workshop status.
```bash
workshop list

# Result
#  WORKSHOP  STATUS  NOTES
#  rkcdev    Ready   -
```

### Run

```bash
workshop run -- run
```

Initial user accounts:

```text
[1] username: root, password: root
[2] username: rkc, password: rkc
```

### Test

```bash
workshop run -- test
```

The Workshop test action runs the QEMU app smoke test suite with QEMU user networking.

### Debug

Start QEMU paused with a GDB server:

```bash
workshop run -- debug
```

The default GDB port is controlled by the Makefile.

### Clean

```bash
workshop run -- clean
```

## Workshop Notes

The repository contains a project-local Workshop SDK under `.workshop/`.

The SDK is responsible for preparing the development environment, including:

* installing Ubuntu packages
* selecting the correct Nim binary for the container architecture
* cloning OpenSBI
* building `fw_jump.bin`

The generated Workshop lock file should not be committed:

```text
.workshop.lock
```

If the Workshop definition or SDK changes, refresh the environment:

```bash
workshop refresh
```

<details><summary>If you run Rk-C on Host, check here</summary>

## Manual Host Setup

The following sections describe how to build and run Rk-C directly on the host
without Workshop.

This is useful if you do not want to use a sandbox, or if you need custom host
networking such as TAP.

## Manual Requirements

* QEMU with RISC-V system emulation
* OpenSBI
* Nim 2.2.10
* clang / lld / LLVM tools
* Python 3
* GNU make
* RISC-V GNU toolchain for building OpenSBI

On Ubuntu-like systems:

```bash
sudo apt install -y \
  qemu-system-misc \
  qemu-utils \
  make \
  clang \
  lld \
  llvm \
  python3 \
  gcc-riscv64-linux-gnu \
  binutils-riscv64-linux-gnu \
  device-tree-compiler
```

## Manual Nim Setup

The current Makefile expects Nim at:

```text
~/nim-2.2.10/bin/nim
```

If your Nim binary is somewhere else, update `NIM` in `Makefile`.

For a local x86_64 install:

```bash
cd ~
wget https://nim-lang.org/download/nim-2.2.10-linux_x64.tar.xz
tar Jxf nim-2.2.10-linux_x64.tar.xz
~/nim-2.2.10/bin/nim --version
```

For a local arm64 install:

```bash
cd ~
wget https://nim-lang.org/download/nim-2.2.10-linux_arm64.tar.xz
tar Jxf nim-2.2.10-linux_arm64.tar.xz
~/nim-2.2.10/bin/nim --version
```

## Manual OpenSBI Setup

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

## Manual Build

```bash
make build
```

Useful variants:

```bash
make build-bins
make build-test-bins
```

## Manual Run

```bash
make run
```

Run with QEMU user networking:

```bash
make run QEMU_NET=user
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

## Manual Tests

Run the QEMU app smoke test suite:

```bash
make test-apps
```

Run tests with QEMU user networking:

```bash
make test-apps QEMU_NET=user
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

## Manual Networking

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

</details>

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

Inside Workshop:

```bash
workshop run -- clean
```

On the host:

```bash
make clean
```

## Notes

* This is a learning and research kernel, not a production OS.
* The ABI and internal service protocols are still evolving.
* The HTTPS/TLS path does not validate certificates yet.
* The network stack is intentionally small and experimental.
