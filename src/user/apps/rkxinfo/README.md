# rkxinfo

`rkxinfo` inspects the RKX header of an application image stored in `/bin`.

It reads only the fixed RKX header through the normal file descriptor API, so it
can inspect applications that are not currently running. This is useful when
checking section layout, requested capabilities, stack pages, and future RKX
metadata before starting a process.

## Usage

```text
rkxinfo <app|/bin/app>
```

Examples:

```text
rkxinfo shell
rkxinfo /bin/curl
```
