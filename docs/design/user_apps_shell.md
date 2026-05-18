# User Apps and Shell

User applications are built as freestanding RISC-V programs and packaged into
RKX images under `/bin`.

## Shell

The shell supports:

- command execution
- cwd management
- foreground and background commands
- redirection
- simple pipelines
- command history
- built-in convenience commands

Most commands are standalone `/bin` programs.

## Applications

Current app categories:

- filesystem: `ls`, `cat`, `mkdir`, `rm`, `rmdir`, `edit`
- process/service: `ps`, `kill`, `svc`
- diagnostics: `date`, `dmesg`, `stracectl`, `rkxinfo`, `ipc`
- networking: `ping`, `nslookup`, `tcpcheck`, `curl`
- tests: `faultcheck`, `capcheck`, `pollcheck`

Each app directory may contain:

- implementation `.nim`
- `README.md`
- `rkx.toml`

## Capabilities

Apps request capabilities in `rkx.toml`. The kernel grants only trusted
capabilities for the executable path, so arbitrary RKX header edits cannot grant
raw access.

Examples:

- `svc` requests service manager control
- `kill` requests process kill
- `stracectl` requests syscall trace control
- normal apps usually request no capabilities

