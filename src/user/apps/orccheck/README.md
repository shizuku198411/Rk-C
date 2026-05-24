# orccheck

`orccheck` is a test-only user program that validates Nim ORC-managed memory on Rk-C.

It links a `malloc`/`free` bridge backed by the process `brk`/`sbrk` syscalls, checks block reuse and trailing heap release, then exercises managed `string`, `seq`, and `ref object` allocations.

## Usage

```text
orccheck
orccheck --help
```

## Current Scope

- Built with `--mm:orc` only for the test binary
- Obtains Nim runtime pages from the Rk-C user heap
- Reuses released allocator blocks and returns released tail storage through `brk`
- Is not included in the normal disk image
