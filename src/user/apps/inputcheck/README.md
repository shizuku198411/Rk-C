# inputcheck

`inputcheck` is a test-only application for validating burst input delivery.

It reads exactly 4096 `x` bytes from standard input and fails when a byte is
missing or corrupted.

## Usage

```text
inputcheck
```

## Notes

- This app is included only in the QEMU smoke-test disk
- It is not packed into the normal production disk image
- The smoke test sends the command and all 4096 payload bytes in one host write
