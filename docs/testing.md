# Test Execution Guide

This guide describes how to run Rk-C's automated and local validation checks.

The main automated test path boots QEMU and runs user-app smoke tests through `scripts/test_apps.py`.

## Prerequisites

Launch the development workshop:

```bash
workshop launch rkc-dev
```

Check status:

```bash
workshop list
```

Expected status:

```text
WORKSHOP  STATUS  NOTES
rkc-dev   Ready   -
```

## Run the Standard Smoke Test

Recommended command:

```bash
workshop run rkc-dev -- test
```

This runs:

```bash
make test-apps TEST_APPS_ARGS="--boot-timeout 60 --command-recover-timeout 30 --qemu-net user --skip-network-smoke"
```

The test boots QEMU, waits for the Rk-C shell, runs app-level smoke cases, and writes a QEMU log under:

```text
build/test_apps_qemu.log
```

## Run Tests Directly

From a prepared development environment:

```bash
make test-apps
```

The default Makefile arguments are:

```text
--boot-timeout 60 --command-recover-timeout 30
```

Pass custom arguments with `TEST_APPS_ARGS`:

```bash
make test-apps TEST_APPS_ARGS="--boot-timeout 90 --command-recover-timeout 45 --qemu-net user --skip-network-smoke"
```

## QEMU Network Options

Use QEMU user networking:

```bash
make test-apps TEST_APPS_ARGS="--qemu-net user --skip-network-smoke"
```

Use TAP networking:

```bash
make test-apps TEST_APPS_ARGS="--qemu-net tap --tap-if tap0"
```

Print host-side TAP setup help:

```bash
make net-host-help
```

Network smoke tests may need TAP networking for ICMP behavior. Under user networking, external ICMP can time out.

## Useful `test_apps.py` Options

```text
--no-build                       skip make build before booting
--qemu-net {user,tap}            choose QEMU networking mode
--tap-if TAP_IF                  TAP interface name
--boot-timeout SECONDS           boot wait timeout
--command-recover-timeout SEC    prompt recovery timeout after command timeout
--log PATH                       QEMU log path
--base-disk PATH                 source disk image
--test-disk PATH                 temporary test disk path
--keep-test-disk                 keep the temporary test disk
--host-ip IP                     host/gateway IP used by network tests
--skip-network-smoke             skip network smoke tests
--network-test-delay SECONDS     delay before network smoke tests
--allowed-failures N             allow up to N failed cases
```

Example:

```bash
python3 scripts/test_apps.py \
  --qemu-net user \
  --skip-network-smoke \
  --boot-timeout 60 \
  --command-recover-timeout 30
```

## Build Test Binaries

Build normal user binaries plus test-only apps:

```bash
make build-test-bins
```

Test-only apps currently include:

```text
faultcheck
capcheck
pollcheck
signalcheck
writecheck
heapcheck
orccheck
```

## Local GitHub Actions Workflow Check

The `rkc-actions` workshop validates GitHub Actions workflow wiring locally with `act`.

Launch it:

```bash
workshop launch rkc-actions
```

List workflow jobs:

```bash
workshop run rkc-actions -- list
```

Check the workflow locally:

```bash
workshop run rkc-actions -- check-workflow
```

This runs:

```bash
act pull_request -j test-apps
```

The local `act` path is intended to validate workflow wiring, including:

* workflow syntax
* event selection
* job ID selection
* `ACT`-specific branch behavior
* checkout behavior
* artifact step wiring

The full Workshop-based QEMU smoke test is skipped under local `act`. Run the actual test with:

```bash
workshop run rkc-dev -- test
```

## CI Behavior

The GitHub Actions workflow runs the QEMU app smoke tests on pull requests and manual dispatch.

In CI, the workflow:

1. checks out the repository,
2. launches the `rkc-dev` Workshop,
3. runs `workshop run rkc-dev -- test`,
4. uploads `build/test_apps_qemu.log` as an artifact when available.

## Clean Before Retesting

To remove generated build artifacts:

```bash
workshop run rkc-dev -- clean
```

Equivalent direct command:

```bash
make clean
```
