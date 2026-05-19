# mv

`mv` renames files or directories through the filesystem service.

## Usage

```text
mv <src>... <dst>
```

When multiple sources are provided, the destination must be an existing
directory. When a single source is provided and the destination is a directory,
the source is moved into that directory with the original name.

## Capabilities

This app does not request privileged RKX capabilities. It uses the regular
filesystem syscall ABI.
