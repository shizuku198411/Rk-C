# Memory, Paging, and Usercopy

Rk-C uses Sv39 paging with a kernel identity map and per-process user address spaces. The memory model is intentionally strict enough to catch kernel bugs while still being small enough to inspect during bring-up.

## Physical Memory Allocator

The kernel page allocator tracks managed physical pages with a bitmap.

```text
physical memory
  -> reserved firmware/kernel/device ranges
  -> bitmap pages
  -> managed page region
```

The allocator exposes development counters through:

- `bitmap` shell built-in
- `/proc/meminfo`
- process memory page counts in `ps`

The allocator zeroes pages when releasing process-owned memory. This matters because userspace process teardown must not leak stale data into later allocations.

## Platform Memory Layout

QEMU and Milk-V use separate memory layout modules under `src/platform/`.

Milk-V Duo 256M reserves known firmware, FDT, ION, kernel, stack, and MMIO-related ranges before exposing a managed memory window. The phase bring-up diagnostics validated:

- kernel load base around `0x80200000`
- managed start after reserved boot assets
- FDT outside the allocator-managed range
- stack outside the allocator-managed range
- bitmap accounting after allocation/free smoke tests

## Kernel Page Table

`enableSv39()` creates a kernel root page table through `createKernelMappedPageTable()`, stores it via `setKernelPageTable()`, writes SATP, and flushes the TLB before continuing.

The kernel mapping is an identity mapping for the runtime physical ranges the kernel needs. Platform-specific paging attributes live under:

```text
src/platform/paging_attrs.nim
src/platform/qemu_virt/paging_attrs.nim
src/platform/milkv_duo256m/paging_attrs.nim
```

This allows board-specific MMIO caching attributes without scattering platform checks in the core paging code.

## User Address Spaces

User programs are RKX images loaded into per-process page tables. Segments are mapped separately:

```text
text    r-x user
rodata  r-- user
data    rw- user
bss     rw- user, zero-filled
stack   rw- user, NX
heap    rw- user, grown by brk/sbrk
```

The kernel rejects overlapping segments, invalid ranges, invalid entry points, unsupported stack sizes, and unknown RKX capability bits before mapping the image.

## Heap and Nim Runtime Allocation

Rk-C now has two userspace allocation paths:

- direct `brk`/`sbrk` heap syscalls
- Nim `osalloc` support for ORC-managed allocation in selected apps/services

The ORC path is backed by `src/user/lib/runtime/orc_osalloc.nim`. It lets apps such as the shell, procfsd, ps, svc, and selected tools move away from large fixed buffers while still using explicit syscall-backed heap growth.

Design constraints:

- kernel memory management remains page-based
- userspace heap growth is per-process
- heap pages must be released when the process is discarded
- kernel code must not depend on Nim's automatic memory management

## Usercopy Boundary

Syscalls that touch user memory must validate pointers before accessing them. The main helpers live in:

```text
src/kernel/mm/usercopy.nim
```

Important helpers include:

- `copyFromUser`
- `copyToUser`
- `copyUserCString`

Validation checks include:

- user virtual address range
- canonical address shape
- mapped PTE existence
- PTE user bit
- read/write permission matching the operation
- page-boundary crossing

SUM is enabled only around the actual copy operation and restored afterward. Kernel code should not leave SUM enabled across arbitrary logic.

## Fault Policy

Fault handling is split by privilege and current process context.

```text
user fault
  -> mark current user process failed/zombie
  -> continue scheduler

kernel fault
  -> panic with trap diagnostics
```

This policy keeps invalid user pointers contained while still making kernel memory bugs loud.

## Developer Checklist

When adding memory-facing code:

- never dereference a user pointer directly
- use usercopy helpers for syscall buffers and C strings
- keep section permissions W^X/NX
- ensure process exit and wait paths release mapped pages
- avoid platform-specific address constants in common memory code
- add procfs or test-app visibility when debugging allocator state
