# QEMU Environment Execution Guide

This guide describes how to build and run Rk-C on the QEMU `virt` machine.

The recommended local environment is Canonical [Workshop](https://ubuntu.com/workshop/docs/). The `rkc-dev` workshop provides the Nim toolchain, QEMU, OpenSBI, and project-local dependencies used by the normal build and run actions.

## Prerequisites

Install LXD and Workshop:

```bash
sudo snap install --channel=6/stable lxd
sudo snap install --classic workshop
```

Launch the development workshop:

```bash
workshop launch rkc-dev
```

Check that it is ready:

```bash
workshop list
```

Expected status:

```text
WORKSHOP  STATUS  NOTES
rkc-dev   Ready   -
```

## Build

Build the kernel and appfs disk image:

```bash
workshop run rkc-dev -- build
```

This runs:

```bash
make build
```

Generated outputs include:

```text
bin/kernel.elf
bin/disk.img
```

Build user binaries without running QEMU:

```bash
workshop run rkc-dev -- build-bins
```

This runs:

```bash
make build-bins
```

## Run

Start Rk-C on QEMU:

```bash
workshop run rkc-dev -- run
```

This runs:

```bash
make run
```

The QEMU target uses:

* `qemu-system-riscv64`
* `-machine virt`
* OpenSBI `fw_jump.bin`
* 256 MiB RAM
* VirtIO block device backed by `bin/disk.img`
* VirtIO network device
* `bin/kernel.elf` as the kernel image

## Login

Initial user accounts:

```text
username: root, password: root
username: rkc,  password: rkc
```

Example shell commands:

```text
Rk-C:/$ help
Rk-C:/$ svc status
Rk-C:/$ ps -l
Rk-C:/$ ls /proc
Rk-C:/$ df
Rk-C:/$ date > /tmp/now.txt
Rk-C:/$ cat /tmp/now.txt
Rk-C:/$ shutdown
```

## Network Modes

The default network mode is TAP:

```bash
workshop run rkc-dev -- run
```

Equivalent direct command:

```bash
make run
```

Default guest/host addressing:

```text
guest IP:   10.0.1.10
host/gw IP: 10.0.1.1
```

Use QEMU user networking instead:

```bash
make run QEMU_NET=user
```

Default user-network settings:

```text
QEMU_USER_NET=10.0.1.0/24
QEMU_USER_HOST=10.0.1.1
QEMU_HOSTFWD=tcp::10080-:80
```

External ICMP may timeout under QEMU user networking. TAP networking is preferred when testing ICMP behavior such as `ping`.

## TAP Host Setup

For manual TAP setup on the host:

```bash
sudo ip tuntap add dev tap0 mode tap user $USER
sudo ip link set tap0 up
sudo ip addr add 10.0.1.1/24 dev tap0
sudo sysctl -w net.ipv4.ip_forward=1
sudo iptables -t nat -A POSTROUTING -s 10.0.1.0/24 -j MASQUERADE
make run QEMU_TAP_IF=tap0
```

You can also print the built-in network help:

```bash
make net-host-help
```

## Debug with GDB

Start QEMU paused with a GDB server:

```bash
workshop run rkc-dev -- debug-qemu
```

Equivalent direct command:

```bash
make qemu-debug
```

By default, the GDB server listens on:

```text
localhost:1234
```

See [Kernel Debugging Guide](debugging.md) for the full two-terminal QEMU and GDB workflow.

## Clean

Remove generated build artifacts:

```bash
workshop run rkc-dev -- clean
```

Equivalent direct command:

```bash
make clean
```

This removes:

```text
build/
bin/
map/
src/generated/
```

## Workshop Refresh

If a Workshop definition or project-local SDK changes, refresh the workshop:

```bash
workshop refresh rkc-dev
```

The generated Workshop lock file should not be committed:

```text
.workshop.lock
```
