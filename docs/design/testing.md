# Testing

Rk-C uses a Python QEMU smoke test runner for end-to-end checks.

## Main Test Command

```bash
make test-apps
```

The test runner:

- builds normal and test-only RKX images
- copies `bin/disk.img` to `bin/test-disk.img`
- packs test-only apps into the test disk
- boots QEMU with the test disk
- verifies boot, shell commands, service commands, procfs, fd operations,
  pipes, redirection, and selected network commands
- verifies security/error cases such as invalid user CString rejection, W^X
  user text, NX stack, and unauthorized capability behavior
- removes `bin/test-disk.img` after completion unless requested otherwise

## Useful Variants

```bash
python3 scripts/test_apps.py --no-build
python3 scripts/test_apps.py --skip-network-smoke
python3 scripts/test_apps.py --keep-test-disk
python3 scripts/test_apps.py --tap-if tap0 --host-ip 10.0.1.1
```

## Test Apps

Test-only apps are not part of the normal appfs image unless the test build path
packs them.

- `faultcheck`: usercopy, W^X, and NX stack checks
- `capcheck`: capability grant/deny behavior
- `pollcheck`: event wait behavior

