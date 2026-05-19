# writecheck

`writecheck` is a test-only application for filesystem write-mode behavior.

## Usage

```text
writecheck
writecheck --help
```

## Behavior

- Exercises `sysWriteFileMode`
- Verifies create plus overwrite
- Verifies append to an existing file
- Verifies overwrite of an existing file
- Verifies append without create fails for a missing file
- Verifies create plus append
- Verifies invalid write flag combinations are rejected

## RKX Metadata

- `stack_pages = 2`
- capabilities: none

## Notes

- This app is intended for the QEMU smoke test suite
- Temporary files are created under `/tmp` and cleaned up before exit
