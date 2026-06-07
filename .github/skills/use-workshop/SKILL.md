---

name: use-workshop
description: Use the Rk-C Workshop environment for build, test, run, kernel debugging, and binary inspection tasks.
-------------------------------------------------------------------------------------------------------------------

# Use Workshop for Rk-C development

Use this skill whenever working on the Rk-C kernel project, especially for build, test, QEMU run, GDB debugging, log inspection, symbol lookup, address lookup, or ELF/binary inspection tasks.

The project uses Canonical Workshop as the canonical development environment. Prefer Workshop commands over running toolchain commands directly on the host.

## Default workshop

Use the `rkc-dev` workshop.

The relevant workshop definition is expected to provide these actions:

* `build`
* `build-bins`
* `test`
* `run`
* `debug-qemu`
* `debug-gdb`
* `objdump`
* `objdump-headers`
* `addr2line`
* `nm`
* `readelf`
* `size`
* `strings`
* `symbols-grep`
* `disasm-symbol`
* `log`
* `clean`

## Core rule

Do not run `make`, QEMU, GDB, Nim, LLVM, binutils, or package-manager setup directly on the host unless the user explicitly asks for host-side commands.

Use:

```bash
workshop run rkc-dev -- <action>
```

## Common commands

### Build the kernel

```bash
workshop run rkc-dev -- build
```

Use this after source changes that affect the kernel, boot flow, memory management, drivers, scheduler, syscall path, or userland integration.

### Build binaries

```bash
workshop run rkc-dev -- build-bins
```

Use this when changes affect build artifacts, user programs, binary packaging, generated outputs, or app images.

### Run tests

```bash
workshop run rkc-dev -- test
```

This is the default verification command for most behavior changes.

The `test` action runs:

```bash
make test-apps TEST_APPS_ARGS="--boot-timeout 60 --command-recover-timeout 30 --qemu-net user --skip-network-smoke"
```

Prefer this over inventing new QEMU test commands.

### Run the kernel manually

```bash
workshop run rkc-dev -- run
```

Use this when the user asks to boot the kernel interactively or inspect runtime behavior manually.

### Clean generated files

```bash
workshop run rkc-dev -- clean
```

Use this when build artifacts appear stale or when a clean rebuild is useful.

## Debugging with QEMU and GDB

The workshop exposes the QEMU GDB stub through the `system` SDK tunnel:

```yaml
plugs:
  gdb:
    interface: tunnel
    endpoint: localhost:1234
```

The project provides two debug actions:

```bash
workshop run rkc-dev -- debug-qemu
```

and:

```bash
workshop run rkc-dev -- debug-gdb
```

`debug-qemu` starts QEMU in debug mode and may wait for GDB. Do not use it as a routine verification command because it may be long-running or interactive.

Use `debug-qemu` only when the user asks for debugging, boot investigation, trap analysis, register inspection, or GDB inspection.

When using GDB:

1. Start QEMU debug mode:

   ```bash
   workshop run rkc-dev -- debug-qemu
   ```

2. In a separate terminal/session, connect GDB:

   ```bash
   workshop run rkc-dev -- debug-gdb
   ```

The `debug-gdb` action runs `gdb-multiarch` against `bin/kernel.elf`, sets the architecture to `riscv:rv64`, disables pagination and confirmation, and connects to `localhost:1234`.

Do not run `gdb-multiarch` directly on the host.

If debugging a 32-bit RISC-V target instead, check the project configuration before changing the architecture setting.

## Binary and ELF inspection

Use the project-provided Workshop actions for binary inspection. Do not run `llvm-objdump`, `llvm-addr2line`, `llvm-nm`, `llvm-readelf`, `llvm-size`, or `strings` directly on the host.

Most inspection actions default to:

```text
bin/kernel.elf
```

Pass another ELF or binary path when needed.

### Disassemble the kernel or another ELF

```bash
workshop run rkc-dev -- objdump
```

This defaults to `bin/kernel.elf`.

To inspect another file:

```bash
workshop run rkc-dev -- objdump bin/user/shell.elf
```

The action uses `llvm-objdump -d --source --line-numbers`.

It writes output to a temporary file, opens it with `less -R` when running interactively, and falls back to `cat` when no TTY is available.

Use this for interactive inspection rather than automated verification.

### Inspect ELF headers, sections, and symbols

```bash
workshop run rkc-dev -- objdump-headers
```

This defaults to `bin/kernel.elf`.

To inspect another file:

```bash
workshop run rkc-dev -- objdump-headers bin/user/shell.elf
```

The action uses `llvm-objdump -h -t`.

Use this when checking sections, symbol tables, or object layout.

### Resolve addresses to source locations

```bash
workshop run rkc-dev -- addr2line 0x80200000
```

This defaults to `bin/kernel.elf`.

To resolve addresses against another ELF:

```bash
workshop run rkc-dev -- addr2line bin/kernel.elf 0x80200000 0x80201234
```

The action uses `llvm-addr2line -f -C -p`.

Use this for panic logs, trap logs, faulting PCs, return addresses, and QEMU/GDB addresses.

When the user provides a raw address from a crash or trap log, prefer `addr2line` before making broad source changes.

### List symbols

```bash
workshop run rkc-dev -- nm
```

This defaults to `bin/kernel.elf`.

To inspect another ELF:

```bash
workshop run rkc-dev -- nm bin/user/shell.elf
```

The action uses `llvm-nm -n -C`.

Use this to check symbol addresses, ordering, missing symbols, or whether a function was linked.

### Search symbols

```bash
workshop run rkc-dev -- symbols-grep trap
```

This searches symbols in `bin/kernel.elf`.

To search another ELF:

```bash
workshop run rkc-dev -- symbols-grep scheduler bin/kernel.elf
```

Use this before guessing symbol names or manually scanning large `nm` output.

### Disassemble one symbol

```bash
workshop run rkc-dev -- disasm-symbol kernel_main
```

This defaults to `bin/kernel.elf`.

To use another ELF:

```bash
workshop run rkc-dev -- disasm-symbol main bin/user/shell.elf
```

The action uses `llvm-objdump --disassemble-symbols`.

Use this when investigating a specific function, trap handler, scheduler path, syscall handler, driver function, or boot routine.

Prefer `disasm-symbol` over full `objdump` when the target function is already known.

### Inspect ELF program and section layout

```bash
workshop run rkc-dev -- readelf
```

This defaults to `bin/kernel.elf`.

To inspect another ELF:

```bash
workshop run rkc-dev -- readelf bin/user/shell.elf
```

The action uses `llvm-readelf -h -l -S`.

Use this for linker script work, load address issues, segment/section layout, entry point checks, and memory mapping problems.

### Inspect binary size and section sizes

```bash
workshop run rkc-dev -- size
```

This defaults to `bin/kernel.elf`.

To inspect another ELF:

```bash
workshop run rkc-dev -- size bin/user/shell.elf
```

The action uses `llvm-size -A -x`.

Use this when checking `.text`, `.rodata`, `.data`, `.bss`, or overall binary growth.

### Inspect embedded strings

```bash
workshop run rkc-dev -- strings
```

This defaults to `bin/kernel.elf`.

To inspect another binary:

```bash
workshop run rkc-dev -- strings bin/user/shell.elf
```

Use this to confirm panic messages, shell commands, app names, static messages, or embedded diagnostic strings.

## Logs

### Inspect test logs

```bash
workshop run rkc-dev -- log
```

This defaults to:

```text
build/test_apps_qemu.log
```

To inspect another log:

```bash
workshop run rkc-dev -- log build/other.log
```

When running interactively, the action opens the log with `less -R`.

When no TTY is available, it prints the last 300 lines.

Use `log` after test failures before changing code.

## Failure investigation workflow

When a Workshop command fails:

1. Read the exact command output first.
2. Inspect the relevant build, test, or helper script before changing source code.
3. Prefer minimal, targeted fixes.
4. Re-run the same Workshop action after the fix.

Useful files and directories to inspect when present:

* `Makefile`
* `scripts/`
* `scripts/test_apps.py`
* `build/`
* `bin/kernel.elf`
* `build/test_apps_qemu.log`

For boot failures:

1. Inspect QEMU output and panic/trap logs.
2. Use `addr2line` on faulting PCs or return addresses.
3. Use `symbols-grep`, `nm`, or `disasm-symbol` for nearby symbols.
4. Inspect linker/layout issues with `readelf` if the failure appears address-related.

For test failures, identify whether the failure is in:

* build
* boot
* shell startup
* app execution
* filesystem/image setup
* networking
* timeout/recovery logic

For address, trap, or instruction-level failures, prefer this flow:

```bash
workshop run rkc-dev -- addr2line <address>
workshop run rkc-dev -- symbols-grep <nearby-name>
workshop run rkc-dev -- disasm-symbol <symbol>
workshop run rkc-dev -- objdump-headers
```

## Networking note

The default `test` action uses QEMU user networking and skips the network smoke test.

Do not assume TAP networking is active unless the workshop definition or user explicitly says so.

## OpenSBI note

The project may use an `opensbi` checkout under `/project/opensbi`.

Do not move OpenSBI into a cache directory unless the user explicitly asks. This layout is intentional because the project also runs in GitHub Actions and new environments may need to clone OpenSBI into the project root.

If OpenSBI already exists, preserve the existing checkout and avoid recloning unless the setup script requires it.

## Editing rules

Before changing code:

1. Identify the subsystem touched by the request.
2. Search for existing helpers and conventions.
3. Keep changes small and consistent with the current style.
4. Do not rewrite large kernel subsystems unless the user explicitly asks.

After changing code:

1. Run the most relevant Workshop action.
2. Prefer `workshop run rkc-dev -- build` for compile-only changes.
3. Prefer `workshop run rkc-dev -- test` for behavior changes.
4. Use `workshop run rkc-dev -- log` when tests fail.
5. Use binary inspection actions when debugging address, symbol, section, or instruction-level problems.
6. Report the exact command run and whether it passed or failed.

## Host safety

Workshop is the intended isolation boundary for development commands.

Do not install packages on the host.

Do not run QEMU directly on the host.

Do not run GDB directly on the host.

Do not run project build commands directly on the host.

Do not run LLVM/binutils inspection commands directly on the host.

Do not modify Workshop definitions unless the task is specifically about the development environment.

## Expected response style

When reporting results, include:

* What changed.
* Which Workshop command was run.
* Whether it passed.
* Any relevant failure output or log path.
* Any address/symbol/log command used during investigation.
* Any follow-up risk or uncertainty.

Keep the report concise and concrete.
