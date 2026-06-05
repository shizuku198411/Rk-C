# Testing

Rk-C uses QEMU-based end-to-end tests plus targeted real-board bring-up logs.

## Main Test Command

The preferred test entry point is:

```bash
workshop run rkc-dev -- test
```

The legacy direct command is:

```bash
make test-apps
```

The workshop command keeps the test environment isolated and closer to CI.

## Test Runner

The Python runner under `scripts/test_apps.py`:

- builds kernel and user RKX images
- builds test-only apps
- creates `bin/test-disk.img`
- packs normal and test apps
- boots QEMU
- logs in through `/bin/login`
- runs shell/app test cases
- reports failed test case numbers and commands

Test cases are split by category under `scripts/app_tests/`.

## Covered Areas

Current smoke coverage includes:

- boot and login
- shell built-ins
- command help
- cwd behavior
- path resolution
- file create/read/write/remove
- chmod/chown and permission checks
- user and group identity
- passwd/shadow authentication paths
- procfs files
- service list/status/log commands
- FD operations
- pipes and redirection
- TTY input behavior
- panic log and dmesg
- heap/brk/sbrk checks
- capability grant/deny behavior
- W^X and NX fault checks
- selected network commands when enabled
- optional hosted toolchain tests when packed

## Network Tests

Network tests may require host TAP setup and are disabled or skipped in environments where external network behavior is expected to be unstable.

Milk-V real-board networking is not part of the current core bring-up test target.

## CI Policy

GitHub Actions runs on Ubuntu default runners, installs QEMU dependencies, and executes app tests without network tests. Because QEMU timing can vary, a small number of failures may be tolerated by policy, but stable repeated failures should be treated as real regressions.

## Real Hardware Validation

Milk-V Duo 256M validation is currently manual and log-driven.

Important bring-up milestones already validated:

- OpenSBI to Rk-C kernel entry
- trap vector setup
- timer interrupts
- DTB parsing
- allocator smoke tests
- Sv39 enablement
- context switching and user task syscall path
- UART RX interrupt input
- SD-backed appfs/rootfs bootstrap
- service startup through login and shell
- status LED on boot and off on shutdown

Real-board logs are kept under `tmp/logs.txt` during active debugging and summarized in roadmap documents under `docs/roadmap/milk-v/`.
