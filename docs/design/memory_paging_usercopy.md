# Memory, Paging, and Usercopy

Rk-C uses Sv39 paging with kernel mappings and per-process user address spaces.

## Physical Memory

The physical allocator tracks managed pages with a bitmap. The `bitmap` shell
command exposes total, used, and free page counts for development.

Kernel memory, device MMIO ranges, and user mappings are kept distinct. User
processes get their own root page table.

## User Mappings

User programs are loaded from RKX images. The loader maps sections separately:

```text
text    r-x user
rodata  r-- user
data    rw- user
bss     rw- user
stack   rw- user, NX
```

This avoids the old single RWX user image mapping and gives useful W^X/NX
coverage.

## Usercopy

Syscalls cross a trust boundary. User pointers are validated before kernel
access through helpers such as:

- `copyFromUser`
- `copyToUser`
- `copyUserCString`

Validation checks include user VA range, canonical address shape, mapped PTEs,
and permissions. SUM is enabled only around the actual copy path and restored
afterward.

## Fault Policy

User faults kill the current user process. Kernel faults panic.

This split keeps kernel bugs visible while allowing invalid user memory accesses
to be contained at process level.

