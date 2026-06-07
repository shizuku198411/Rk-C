# Kernel Debugging Guide

This guide describes how to debug the Rk-C kernel with QEMU's GDB stub.

Use the `rkc-dev` Workshop environment for the normal debug flow. It provides the RISC-V QEMU target, OpenSBI artifacts, `gdb-multiarch`, and the GDB tunnel used by the project.

## Prerequisites

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

Build the kernel before starting a debug session:

```bash
workshop run rkc-dev -- build
```

This produces the kernel image used by GDB:

```text
bin/kernel.elf
```

## Start QEMU for Debugging

In the first terminal, start QEMU paused with the GDB stub enabled:

```bash
workshop run rkc-dev -- debug-qemu
```

This runs:

```bash
make qemu-debug
```

The QEMU debug target starts with `-S`, so the virtual machine waits for GDB before executing guest code. This command is long-running and should stay open for the duration of the debug session.

By default, the GDB stub is exposed on:

```text
localhost:1234
```

The tunnel is declared in `.workshop/rkc-dev.yaml` through the `system` SDK:

```yaml
plugs:
  gdb:
    interface: tunnel
    endpoint: localhost:1234
```

## Connect GDB

In a second terminal, connect GDB through Workshop:

```bash
workshop run rkc-dev -- debug-gdb
```

This runs:

```bash
gdb-multiarch bin/kernel.elf \
  -ex "set architecture riscv:rv64" \
  -ex "set pagination off" \
  -ex "set confirmation off" \
  -ex "target remote localhost:1234"
```

Once connected, set breakpoints and continue execution:

```gdb
break kmain
continue
```

Use the symbol or function that matches the area being investigated. For example, trap and syscall work usually starts around the kernel trap or syscall dispatch paths.

## Typical Session

Terminal 1:

```bash
workshop run rkc-dev -- debug-qemu
```

Terminal 2:

```bash
workshop run rkc-dev -- debug-gdb
```

Then in GDB:

```gdb
break kmain
continue
bt
info registers
```

## Notes

Use `debug-qemu` only for interactive debugging. It can block while QEMU waits for GDB.

For ordinary build verification, use:

```bash
workshop run rkc-dev -- build
```

For smoke tests, use:

```bash
workshop run rkc-dev -- test
```
