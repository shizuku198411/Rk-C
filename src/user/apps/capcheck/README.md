# capcheck

`capcheck` is a test-only application for the RKX capability grant policy.

It intentionally requests capabilities that should not be granted to this app,
then checks that the kernel strips them from the effective capability mask and
rejects protected syscalls or protected service actions.

## Usage

```text
capcheck
capcheck --help
```

## Behavior

- Reads its own `/proc/<pid>/status`
- Verifies requested capabilities are visible
- Verifies effective capabilities are stripped to `none`
- Confirms raw network and process-list syscalls are denied
- Sends a forged process-kill request and confirms `procmgtd` denies it

## RKX Metadata

- `stack_pages = 4`
- requested capabilities:
  - `sys_service_manager`
  - `sys_raw_fs`
  - `sys_raw_block`
  - `sys_raw_net`
  - `sys_process_list`
  - `sys_process_kill`

The kernel policy intentionally does not grant these capabilities to
`/bin/capcheck`. This app exists to test that behavior.

## Notes

- This app is included by the QEMU smoke test suite as a test-only binary
- It is not packed into the normal disk image
