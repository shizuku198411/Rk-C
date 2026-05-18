# Boot and Architecture

Rk-C targets QEMU `virt` on RISC-V 64-bit. The firmware path is OpenSBI
`fw_jump`, which enters the kernel in S-mode.

## Boot Flow

```text
OpenSBI
  -> src/arch/riscv64/boot.S
  -> kernel_main
  -> bootstrap
  -> boot task
  -> svcmgtd
  -> managed services
  -> shell
```

Early boot performs:

- BSS clear
- global pointer and stack setup
- trap vector setup
- physical memory allocator initialization
- process table initialization
- Sv39 enablement
- filesystem and appfs initialization
- timer interrupt enablement

The kernel then creates a boot task. The boot task starts `svcmgtd`, waits for
required services, waits for optional services until timeout, and starts the
interactive shell after the service startup pass is complete.

## Kernel/User Split

The kernel keeps mechanisms that need privilege or direct hardware access:

- traps and syscall dispatch
- page allocation and page table management
- process table and context switching
- IPC queues
- service registry
- raw VirtIO access
- RKX image loading

Most OS policy is pushed into userland services:

- service management: `svcmgtd`
- process service API: `procmgtd`
- block I/O server: `blockd`
- filesystem server: `fsd`
- procfs server: `procfsd`
- network server: `netd`

## Service Startup

Managed services are defined in `src/lib/service_catalog.nim`.

Required services:

- `procmgtd`
- `blockd`
- `fsd`

Optional services:

- `procfsd`
- `netd`

Optional services can become degraded. Required services are restart targets.

