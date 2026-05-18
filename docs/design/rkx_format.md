# RKX Executable Format

RKX is Rk-C's compact user executable format.

User programs are linked as freestanding RISC-V ELF files and converted by:

```text
scripts/make_rkx.py
```

## Header

The shared header definition is:

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

## Per-App Metadata

Each app/server can define RKX packaging metadata in `rkx.toml`:

```toml
schema_version = 1
stack_pages = 2
capabilities = []
```

`make_rkx.py` reads this metadata and writes the RKX header.

## Loader Validation

The kernel RKX loader validates:

- magic and version
- header size
- segment file ranges
- page alignment
- expected user VA range
- entry inside text
- segment non-overlap
- stack page limits

## Inspection

Runtime process mappings are visible through:

```text
/proc/<pid>/rkx_map
```

On-disk RKX headers can be inspected without starting the app:

```text
rkxinfo curl
rkxinfo /bin/svcmgtd
```

