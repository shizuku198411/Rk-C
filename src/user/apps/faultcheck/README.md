# faultcheck

`faultcheck` is a test-only application used by the QEMU smoke test suite.
It intentionally exercises user/kernel boundary and memory permission failures.

## Usage

```text
faultcheck <bad-cstring|write-text|exec-stack>
faultcheck --help
```

## Modes

- `bad-cstring`
  - Passes an invalid user CString to `sysOpen`
  - Expects the kernel to reject it without accepting the pointer
- `write-text`
  - Attempts to write to the user text segment
  - Expects a user-mode store page fault and process kill
- `exec-stack`
  - Attempts to execute code from the user stack
  - Expects a user-mode instruction page fault and process kill

## Notes

- This app is not packed into the normal disk image
- It is included by the test runner through the test-only app build path
- It is meant to validate RKX segment permissions, NX stack behavior, and
  usercopy rejection behavior
