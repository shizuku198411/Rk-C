# chown

`chown` changes the owner stored in rootfs or tmpfs file metadata.

## Usage

```text
chown <uid>:<gid> <path>
chown <root|rkc> <path>
```

Examples:

```text
chown rkc /tmp/note.txt
chown 0:0 /tmp/root-owned.txt
```

Only root can change ownership. The app does not require RKX capabilities;
ownership is controlled by the normal filesystem permission syscall.
