# User Apps and Shell

User applications are freestanding RISC-V programs packaged as RKX images and installed under `/bin`.

## Userland Runtime

User apps use shared libraries under `src/user/lib/`.

```text
src/user/lib/core/      arguments, IO, paths, heap, app helpers, passwd/group/shadow clients
src/user/lib/ipc/       request/reply helpers
src/user/lib/net/       DNS, TCP, HTTP, TLS helpers
src/user/lib/runtime/   Nim ORC osalloc support
src/user/lib/syscall/   domain-specific syscall wrappers
```

`src/user/lib/core/syscall.nim` re-exports the split syscall wrapper modules to preserve a stable import path.

## Args and Help

Applications receive a raw argument string. `src/user/lib/core/args.nim` converts it into a small argc/argv-like structure.

Common app helpers in `src/user/lib/core/app.nim` provide:

- `parseArgsOrExit`
- `exitIfHelp`
- argc validation helpers
- usage/error exits

The shell only lists available commands. Detailed help belongs to each app through `--help`.

## Shell Structure

The shell is split into focused modules:

```text
src/user/apps/shell/
  shell.nim
  state.nim
  prompt.nim
  history.nim
  line_editor.nim
  builtins.nim
  command.nim
  command_completion.nim
  help.nim
  internal/command_parse.nim
  internal/command_execute.nim
```

Features:

- prompt with current user and cwd
- command history
- command completion
- built-ins such as `cd`, `pwd`, `su`, `ticks`, `traps`, `bitmap`, `history`, `shutdown`
- foreground/background execution
- simple pipelines
- output redirection
- cwd inheritance into child processes

## Login and User Identity

Boot starts `/bin/login`, not `/bin/shell` directly.

```text
login
  -> authenticate through userd
  -> set cwd to user's home
  -> exec_as /bin/shell with uid/gid
  -> wait for shell exit
  -> return to login prompt
```

Default users:

| User | UID | GID | Home |
| --- | --- | --- | --- |
| `root` | 0 | 0 | `/` |
| `rkc` | 1000 | 1000 | `/home/rkc` |

`sudo` and `su` authenticate through userd before changing effective user context.

## Apps

Current app categories:

- filesystem: `ls`, `cat`, `mkdir`, `rm`, `rmdir`, `touch`, `cp`, `mv`, `df`, `wc`, `edit`
- process/service: `ps`, `kill`, `svc`
- user/account: `login`, `id`, `whoami`, `sudo`, `passwd`, `chmod`, `chown`
- diagnostics: `date`, `dmesg`, `paniclog`, `stracectl`, `rkxinfo`, `ipc`, `which`
- networking: `ping`, `nslookup`, `tcpcheck`, `curl`
- system: `shutdown`
- tests: `faultcheck`, `capcheck`, `pollcheck`, `signalcheck`, `writecheck`, `heapcheck`, `inputcheck`, `orccheck`

## Hosted Toolchain

The optional `modules/rkc-toolchain` submodule can provide hosted development tools such as assembler/compiler/linker utilities. When `/bin/rkcstdlib` exists and the split standard library files are missing, boot may run:

```text
/bin/rkcstdlib --install
```

This installs headers and object libraries under:

```text
/usr/include/rkc_*.h
/usr/lib/rkc_*.rko
```

The toolchain is optional. Platforms may skip network or hosted-toolchain related startup policy when those features are not part of the current bring-up target.

## Memory Allocation

Older apps used fixed buffers. Selected apps and services now use Nim ORC allocation backed by `osalloc`.

Examples:

- shell state and command buffers
- procfsd render buffers
- ps and svc output helpers

Kernel code should not depend on ORC. This is a userspace runtime feature.
