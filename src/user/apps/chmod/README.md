# chmod

`chmod` changes the Unix-style permission bits stored in rootfs or tmpfs file
metadata.

## Usage

```text
chmod <octal-mode> <path>
```

Examples:

```text
chmod 600 /tmp/private.txt
chmod 755 /tmp/tools
```

Only root or the file owner can change mode bits. The app does not require any
capabilities because filesystem permissions are separate from RKX capabilities.
