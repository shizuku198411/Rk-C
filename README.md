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

Rk-C is a microkernel-style operating system for RISC-V 64bit, implemented in Nim.

It targets QEMU's `virt` machine and boots through OpenSBI. The kernel and userland
applications are built as freestanding RISC-V binaries, then packed into a disk
image that is mounted at boot.

## Overview

- Target architecture: RISC-V 64bit
- Language: Nim
- Emulator: QEMU
- Firmware: OpenSBI
- Boot image: ELF kernel loaded by QEMU
- Userland: standalone user applications loaded from `/bin`

## Features

- OpenSBI-based kernel boot
- RISC-V trap handling and syscall dispatch
- U-mode user process execution
- Cooperative/preemptive process scheduling groundwork
- Console input/output through syscall
- VirtIO MMIO block device support
- Disk-backed filesystem support
- VFS-style mount points
- `/bin` application loading from disk image
- `/tmp` tmpfs mount
- Userland shell
- User commands: `ls`, `cat`, `mkdir`, `rm`, `rmdir`, `ps`, `date`, `edit`
- File editor with cursor movement, save/exit commands, and fixed header/help/status lines

## Build
### 1. install required package
```bash
sudo apt install -y \
  qemu-system-misc \
  make \
  riscv64-linux-gnu
```

### 2. install Nim (pre-built binaries)
```bash
# Please download the pre-built binaries that matches your env's architecture
# check: https://nim-lang.org/install_unix.html

cd ~
wget https://nim-lang.org/download/nim-2.2.10-linux_<arch>.tar.xz
tar Jxfv nim-2.2.10-linux_<arch>.tar.xz
rm nim-2.2.10-linux_<arch>.tar.xz

# set nim path
echo "export PATH=$PATH:~/nim-2.2.10/bin" >> ~/.bashrc
source ~/.bashrc

# check nim version
nim --version
```

### 3. build OpenSBI
```bash
cd Rk-C

# clone opensbi git
git clone https://github.com/riscv-software-src/opensbi.git
cd opensbi

# checkout to v1.8.1
git checkout v1.8.1

# build
export CROSS_COMPILE=riscv64-linux-gnu-
make PLATFORM=generic

# verify firmware
ls -l build/platform/generic/firmware/fw_jump.bin
```

### 4. build Rk-C
```bash
cd Rk-C
make build
```

## Run Rk-C
```bash
make run
```

```text
# Once the kernel has successfully booted, the shell will start.

type 'help' for commands
Rk-C:$ help
commands:
  help                show this help
  ls [-l] [path]      list directory
  cat <path>          print file
  mkdir <path>        create directory
  rm <path>           remove file
  rmdir <path>        remove empty directory
  edit <path>         edit file
  ps                  show process slots
  date                show current time
  ticks               show timer ticks
  exit                exit shell
  shutdown            shutdown kernel
```
