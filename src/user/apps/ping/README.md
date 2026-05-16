# ping

`ping` sends a single ICMP echo request through `netd`.

## Usage

```text
ping [ip]
ping --help
```

Default target:

```text
10.0.1.1
```

## Behavior

- Parses an optional IPv4 target
- Resolves `netd` from the service registry
- Sends `SysIpcOpNetPingRequest`
- Waits for `SysIpcOpNetPingResponse`
- Prints either a reply or timeout message

## Notes

- This sends one ping request, not a continuous stream
- It exits with status `1` when `netd` is unavailable or the request times out
