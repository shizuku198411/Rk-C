# mv

`mv` renames files or directories through the filesystem service. When the
kernel cannot rename a regular file directly, such as across filesystem
mounts, the command falls back to copy-and-unlink.

## Usage

```text
mv <src>... <dst>
```

When multiple sources are provided, the destination must be an existing
directory. When a single source is provided and the destination is a directory,
the source is moved into that directory with the original name.

Directory moves require a direct filesystem rename. Cross-filesystem fallback
is only supported for regular files.

## Capabilities

This app does not request privileged RKX capabilities. It uses the regular
filesystem syscall ABI.
