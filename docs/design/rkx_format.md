# RKX Executable Format

RKX is Rk-C's compact user executable format. User programs are linked as freestanding RISC-V ELF files and converted to RKX images for appfs installation under `/bin`.

## Tooling

Host-side conversion is handled by:

```text
scripts/make_rkx.py
```

Optional hosted tooling can also produce or inspect RKX artifacts inside Rk-C when the `modules/rkc-toolchain` submodule is available.

Useful tools:

```text
rkxinfo /bin/curl
rkxinfo curl
rkas
rkld
rkcc
cc
rkcstdlib --install
```

## Header Definition

The shared RKX header lives in:

```text
src/lib/rkx.nim
```

The header stores:

- magic
- version
- header size
- requested capability mask
- entry virtual address
- text VA, file offset, file size, memory size
- rodata VA, file offset, file size, memory size
- data VA, file offset, file size, memory size
- bss VA and memory size
- stack pages
- flags
- allowed UID count
- allowed UID list

## Segment Layout

The loader maps sections with separate permissions:

```text
text    r-x
rodata  r--
data    rw-
bss     rw- zero-filled
stack   rw- NX
heap    rw- grown later by brk/sbrk
```

The entry point must be inside executable text.

## App Metadata

Each app or server can provide `rkx.toml`:

```toml
schema_version = 1
stack_pages = 2
capabilities = []
allowed_uids = []
```

Capabilities are requests only. The kernel grants the intersection of the RKX request and the trusted path policy.

`allowed_uids` is encoded into the RKX header. An empty list means every UID may execute the image. A non-empty list restricts execution to those numeric UIDs.

## Loader Validation

The kernel loader validates:

- magic and version
- header size
- supported capability bits
- segment file ranges
- segment page alignment
- user virtual address range
- non-overlapping segments
- entry inside text
- stack page limits
- allowed UID count not exceeding `RkxAllowedUidMax`

Images with unknown capability bits are rejected.

## Capability Grant

The effective process capability mask is:

```text
effective = rkx_header.requested_caps & trustedCapsForPath(executable_path)
```

Both requested and granted masks are stored in process metadata and exposed through procfs.

## Inspection

Runtime mappings:

```text
/proc/<pid>/rkx_map
```

On-disk header inspection:

```text
rkxinfo /bin/svcmgtd
rkxinfo curl
```

`rkxinfo` shows the requested RKX capability mask. It does not prove that the kernel granted those capabilities.
