# pollcheck

`pollcheck` is a test-only application for the poll-style event wait syscall.
It checks timer, pipe readability/writability, IPC-empty, and invalid-fd events.

## Usage

```text
pollcheck
pollcheck --help
```

## Notes

- This app is included by the QEMU smoke test suite as a test-only binary
- It is not packed into the normal disk image
