# Rk-C Design Notes

This directory contains developer-oriented design notes for Rk-C.

The top-level project README stays intentionally short and focuses on what Rk-C is, how to build it, and how to run it. The documents here describe subsystem boundaries, runtime flows, ABI contracts, hardware backends, and implementation constraints that matter when changing the kernel or userland services.

## Reading Order

```text
boot_architecture
  -> platforms_hardware
  -> memory_paging_usercopy
  -> process_scheduler
  -> trap_syscall_abi
  -> ipc_services
  -> filesystem_fd_procfs
  -> user_apps_shell
  -> networking
```

## Documents

- [Boot and Architecture](boot_architecture.md)
- [Platform and Hardware Backends](platforms_hardware.md)
- [Memory, Paging, and Usercopy](memory_paging_usercopy.md)
- [Process, Scheduler, and Lifecycle](process_scheduler.md)
- [Trap and Syscall ABI](trap_syscall_abi.md)
- [Capability Model](capabilities.md)
- [RKX Executable Format](rkx_format.md)
- [IPC and Services](ipc_services.md)
- [Filesystem, FD, and Procfs](filesystem_fd_procfs.md)
- [Networking](networking.md)
- [User Apps and Shell](user_apps_shell.md)
- [Testing](testing.md)

## Maintenance Rules

- Keep this directory aligned with `src/`, not only with the roadmap files.
- Prefer concrete paths and constants when they are part of the ABI or hardware contract.
- Document platform-specific behavior through the platform dispatcher model instead of mixing QEMU and Milk-V details into one generic paragraph.
- When a design uses IPC, mention both the kernel syscall boundary and the userspace service protocol.
